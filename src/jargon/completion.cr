require "./schema"

module Jargon
  # Shell completion: generates a small "shim" script per shell that, on every
  # Tab, forwards the cursor position and typed words to the program itself
  # (the hidden `__complete` verb). The program then computes candidates from
  # the schema plus any registered dynamic completers — so static (flags,
  # enums, subcommands) and dynamic (live app data) completion share one path.
  class Completion
    # Hidden subcommand the generated shim invokes at completion time. Never
    # written by the developer — it is an internal token between the shim and
    # CLI#handle_completion.
    COMPLETE_VERB = "__complete"

    # Context handed to a registered completer block. `partial` is the token
    # being completed; `words` is the full command line as the shell tokenized
    # it (program name at index 0); `subcommand` is the resolved subcommand
    # path (nil at top level); `arguments` is a lenient parse of what has been
    # typed so far, for filtering.
    struct Context
      getter partial : String
      getter words : Array(String)
      getter subcommand : String?
      getter arguments : Hash(String, String)

      def initialize(@partial : String, @words : Array(String), @subcommand : String?, @arguments : Hash(String, String))
      end
    end

    def initialize(@cli : CLI)
      @words = [] of String
    end

    # ---- shim generation -------------------------------------------------

    # Bash splits words at `=` and `:` (they are in COMP_WORDBREAKS), so
    # `--mode=fa` arrives as `--mode`, `=`, `fa`. The shim rejoins pieces that
    # have no whitespace between them in COMP_LINE, so the program sees the
    # same words zsh and fish report, then trims each candidate back to the
    # part after the last break, which is all readline replaces.
    def bash(command : String) : String
      program = @cli.program_name
      func = "_#{sanitize(program)}_complete"
      <<-BASH
        #{func}() {
            local brk=${COMP_WORDBREAKS//[^=:]} rest=$COMP_LINE word gap i j=-1 cword=0 prefix=
            local -a words=()
            for ((i = 0; i < ${#COMP_WORDS[@]}; i++)); do
                word=${COMP_WORDS[i]}
                if [[ -z $word ]]; then gap=$rest; else gap=${rest%%"$word"*}; rest=${rest#*"$word"}; fi
                if [[ -n $brk && $j -ge 0 && -z $gap && ( $word == [$brk]* || ${words[j]} == *[$brk] ) ]]; then
                    words[j]+=$word
                else
                    words[++j]=$word
                fi
                ((i == COMP_CWORD)) && cword=$j
            done
            [[ -n $brk && ${words[cword]} == *[$brk]* ]] && prefix=${words[cword]%"${words[cword]##*[$brk]}"}
            readarray -t COMPREPLY < <(#{sh_quote(command)} #{COMPLETE_VERB} "$cword" "${words[@]}")
            if [[ -n $prefix ]]; then COMPREPLY=("${COMPREPLY[@]#"$prefix"}"); fi
        }
        complete -F #{func} #{sh_quote(program)}
        BASH
    end

    def zsh(command : String) : String
      program = @cli.program_name
      func = "_#{sanitize(program)}"
      # `#compdef` is a comment compinit parses, so quoting can't make an
      # unusual name safe there; the explicit `compdef` call covers it.
      header = plain_word?(program) ? "#compdef #{program}\n" : ""
      <<-ZSH
        #{header}#{func}() {
            local -a candidates
            candidates=("${(@f)$(#{sh_quote(command)} #{COMPLETE_VERB} $((CURRENT - 1)) $words)}")
            compadd -U -- $candidates
        }
        compdef #{func} #{sh_quote(program)}
        ZSH
    end

    def fish(command : String) : String
      program = @cli.program_name
      func = "__#{sanitize(program)}_complete"
      <<-FISH
        function #{func}
            set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
            set -l current (commandline --current-token)
            #{fish_quote(command)} #{COMPLETE_VERB} (count $tokens) $tokens $current
        end
        complete -c #{fish_quote(program)} -f -a '(#{func})'
        FISH
    end

    private def sanitize(name : String) : String
      name.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    # Words made only of these characters need no quoting in bash, zsh, or
    # fish, so ordinary command names and paths render unchanged.
    private def plain_word?(word : String) : Bool
      word.valid_encoding? && word.matches?(/\A[A-Za-z0-9_.\/+:@,-]+\z/)
    end

    # Quote a word for bash/zsh (POSIX single quotes).
    private def sh_quote(word : String) : String
      plain_word?(word) ? word : "'#{word.gsub("'", %q('\''))}'"
    end

    # Quote a word for fish, whose single quotes honor `\\` and `\'` escapes.
    private def fish_quote(word : String) : String
      plain_word?(word) ? word : "'#{word.gsub("\\", "\\\\").gsub("'", "\\'")}'"
    end

    # ---- runtime engine --------------------------------------------------

    # Compute completion candidates for a tokenized command line. `words`
    # includes the program name at index 0; `cword` is the index of the word
    # under the cursor (may equal words.size when completing a fresh token).
    def candidates(words : Array(String), cword : Int32) : Array(String)
      @words = words
      partial = (cword >= 0 && cword < words.size) ? words[cword] : ""
      args = words.size > 1 ? words[1..] : [] of String
      complete_cli(@cli, args, cword - 1, "", partial)
    end

    private def complete_cli(cli : CLI, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)
      unless cli.subcommands.empty?
        default = cli.default_subcommand

        # Completing the subcommand token itself, which may instead be the
        # default subcommand's first word.
        if cursor <= 0
          names = cli.subcommands.keys
          names += ["--help", "-h"] if partial.starts_with?("-")
          candidates = filter(names, partial)
          candidates += complete_subcommand(cli, default, args, cursor, path, partial) if default
          return candidates.uniq
        end

        # Descend into the chosen subcommand, which may be abbreviated, or,
        # when the first word names none, into the default subcommand with
        # every word, as `parse` does.
        if name = args[0]?.try { |arg| cli.resolve_subcommand(arg) }
          return complete_subcommand(cli, name, args[1..], cursor - 1, path, partial)
        end
        return default ? complete_subcommand(cli, default, args, cursor, path, partial) : [] of String
      end

      if schema = cli.schema
        return complete_schema(schema, args, cursor, path, partial)
      end

      [] of String
    end

    private def complete_subcommand(cli : CLI, name : String, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)
      sub_path = join(path, name)
      case sub = cli.subcommands[name]?
      when CLI    then complete_cli(sub, args, cursor, sub_path, partial)
      when Schema then complete_schema(sub, args, cursor, sub_path, partial)
      else             [] of String
      end
    end

    private def complete_schema(schema : Schema, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)
      # After a POSIX `--` every word is an operand, never a flag.
      unless args.first(cursor.clamp(0, args.size)).includes?("--")
        if candidates = flag_word_candidates(schema, args, cursor, path, partial)
          return candidates
        end
      end

      # Completing a positional.
      if field = positional_at(schema, args, cursor)
        return value_candidates(schema, field, path, partial, args) || [] of String
      end

      [] of String
    end

    # Candidates when the word under the cursor is a flag or a flag's value;
    # nil when it is an operand.
    private def flag_word_candidates(schema : Schema, args : Array(String), cursor : Int32, path : String, partial : String) : Array(String)?
      # Completing the value half of a `--flag=value` word. Candidates keep
      # the `--flag=` prefix, since the shell replaces the whole word.
      if partial.starts_with?("--") && (eq = partial.index('='))
        field = field_for_flag(partial, schema)
        return [] of String if field.nil? || boolean?(schema, field)
        values = value_candidates(schema, field, path, partial[(eq + 1)..], args) || [] of String
        return values.map { |value| partial[..eq] + value }
      end

      # Completing a flag name.
      return flag_name_candidates(schema, partial) if partial == "-" || flag_token?(partial)

      # Completing the value of the preceding value-taking flag. This is
      # terminal: the current token IS that flag's value, so never fall
      # through to positional completion (an absent enum/completer just
      # means no candidates).
      if cursor >= 1 && (prev = args[cursor - 1]?) && (field = value_flag_field(schema, prev))
        value_candidates(schema, field, path, partial, args) || [] of String
      end
    end

    private def value_candidates(schema : Schema, field : String, path : String, partial : String, args : Array(String)) : Array(String)?
      key = path.empty? ? field : "#{path}.#{field}"
      if completer = @cli.completers[key]?
        ctx = Context.new(partial, @words, path.empty? ? nil : path, collect_arguments(schema, args))
        return completer.call(ctx)
      end

      if (prop = props_of(schema)[field]?) && (enum_values = prop.enum_values)
        return filter(enum_values.map { |v| v.as_s? || v.to_json }, partial)
      end

      nil
    end

    private def flag_name_candidates(schema : Schema, partial : String) : Array(String)
      positional = schema.positional
      tokens = ["--help", "-h"]
      props_of(schema).each do |name, prop|
        next if positional.includes?(name)
        tokens << "--#{name}"
        tokens << "-#{prop.short}" if prop.short
      end
      filter(tokens, partial)
    end

    # Which positional slot the cursor sits in, accounting for flags (and the
    # values non-boolean flags consume). Returns the last positional when it is
    # a variadic array and the cursor is past the declared slots.
    private def positional_at(schema : Schema, args : Array(String), cursor : Int32) : String?
      names = schema.positional
      return if names.empty?

      idx = positional_index(schema, args, Math.min(cursor, args.size))
      return names[idx] if idx < names.size

      last = names.last?
      (last && array?(schema, last)) ? last : nil
    end

    # Count how many positional slots are filled within args[0...limit],
    # skipping flags and the values that value-taking flags consume. Mirrors
    # the parser: an open slot takes any non-flag word (`k=v` and `-5`
    # included), and every word after `--` is an operand.
    private def positional_index(schema : Schema, args : Array(String), limit : Int32) : Int32
      idx = 0
      i = 0
      options_ended = false
      while i < limit
        tok = args[i]
        if !options_ended && tok == "--"
          options_ended = true
          i += 1
        elsif !options_ended && value_flag_field(schema, tok) && i + 1 < limit
          i += 2
        elsif !options_ended && flag_token?(tok)
          i += 1
        else
          idx += 1
          i += 1
        end
      end
      idx
    end

    # A leading dash marks a flag, except a lone `-` and a negative number
    # like `-5`, which the parser reads as values.
    private def flag_token?(token : String) : Bool
      token.starts_with?("-") && token.size > 1 && !token[1].ascii_number?
    end

    # The field a flag sets when it takes the following word as its value
    # (`--name`, `-n`); nil for booleans, `--name=value`, and non-flags.
    private def value_flag_field(schema : Schema, token : String) : String?
      return if !flag_token?(token) || token.includes?("=")
      if (field = field_for_flag(token, schema)) && !boolean?(schema, field)
        field
      end
    end

    private def collect_arguments(schema : Schema, args : Array(String)) : Hash(String, String)
      result = {} of String => String
      i = 0
      while i < args.size
        tok = args[i]
        break if tok == "--" # the rest are literal operands
        if tok.starts_with?("--") && tok.includes?("=")
          k, v = tok[2..].split("=", 2)
          result[k] = v
          i += 1
        elsif flag_token?(tok)
          field = field_for_flag(tok, schema)
          if field && !boolean?(schema, field) && i + 1 < args.size
            result[field] = args[i + 1]
            i += 2
          else
            result[field || tok] = "true"
            i += 1
          end
        elsif tok.includes?("=")
          k, v = tok.split("=", 2)
          result[k] = v
          i += 1
        else
          i += 1
        end
      end
      result
    end

    # ---- small schema helpers --------------------------------------------

    private def props_of(schema : Schema) : Hash(String, Property)
      schema.root.properties || {} of String => Property
    end

    private def field_for_flag(token : String, schema : Schema) : String?
      if token.starts_with?("--")
        name = token[2..].split("=", 2)[0]
        props_of(schema).has_key?(name) ? name : nil
      elsif token.starts_with?("-")
        short = token[1..]
        props_of(schema).each { |field, prop| return field if prop.short == short }
        nil
      end
    end

    private def boolean?(schema : Schema, field : String) : Bool
      props_of(schema)[field]?.try(&.type.boolean?) || false
    end

    private def array?(schema : Schema, field : String) : Bool
      props_of(schema)[field]?.try(&.type.array?) || false
    end

    private def join(path : String, name : String) : String
      path.empty? ? name : "#{path}.#{name}"
    end

    private def filter(candidates : Array(String), partial : String) : Array(String)
      return candidates if partial.empty?
      candidates.select(&.starts_with?(partial))
    end
  end
end
