require "./yaml_reader"
require "./schema"
require "./result"
require "./config"
require "./help"
require "./validator"
require "./completion"

module Jargon
  # Option defaults for `CLI#parse`, `CLI#json`, and `CLI#run` (e.g. from
  # `CLI#load_config`): a JSON object, parsed or as a hash. They rank below
  # CLI arguments and environment variables.
  alias Defaults = JSON::Any | Hash(String, JSON::Any)

  # A command-line parser driven by one or more schemas. A CLI is either *flat*
  # (a single `schema`) or in *subcommand mode* (a map of named `subcommands`,
  # each its own Schema or nested CLI). Build one with `Jargon.cli`/`Jargon.new`,
  # then `parse` arguments into a `Result`, `json` straight to validated data,
  # or `run` to also handle `--help`, completion, and error exits.
  class CLI
    # Alone on a command line, or after the subcommand, it reads options as
    # JSON from stdin (`xerp mark -@ < options.json`).
    STDIN_JSON = "-@"

    getter schema : Schema?
    getter program_name : String
    getter subcommands : Hash(String, Schema | CLI)
    getter default_subcommand : String?
    getter subcommand_key : String
    getter completers : Hash(String, Proc(Completion::Context, Array(String)))
    getter? bare_assignment : Bool = true
    property output : IO = STDOUT

    # Create a CLI from a JSON schema string.
    # Auto-detects multi-doc format (relaxed JSONL) for subcommands.
    def self.from_json(json : String, program_name : String = "cli") : CLI
      if multi_json?(json)
        cli = CLI.new(program_name)
        cli.load_multi_json(json)
        cli
      else
        schema = Schema.from_json(json)
        CLI.new(schema, program_name)
      end
    end

    # Create a CLI from a JSON or YAML schema file.
    # Auto-detects multi-doc format for subcommands.
    def self.from_file(path : String, program_name : String = "cli") : CLI
      content = File.read(path)
      if path.ends_with?(".yaml") || path.ends_with?(".yml")
        from_yaml(content, program_name)
      else
        from_json(content, program_name)
      end
    end

    # Create a CLI from a YAML schema string.
    # Auto-detects multi-doc format for subcommands.
    def self.from_yaml(yaml : String, program_name : String = "cli") : CLI
      if multi_yaml?(yaml)
        cli = CLI.new(program_name)
        cli.load_multi_yaml(yaml)
        cli
      else
        json = YAMLReader.parse(yaml).to_json
        from_json(json, program_name)
      end
    end

    # Check if YAML content has multiple documents
    protected def self.multi_yaml?(content : String) : Bool
      YAMLReader.parse_all(content).size > 1
    end

    # Check if JSON content has multiple objects (relaxed JSONL)
    protected def self.multi_json?(content : String) : Bool
      # Count top-level opening braces by tracking depth
      stripped = content.strip
      return false unless stripped.starts_with?('{')

      count = 0
      depth = 0
      in_string = false
      escape_next = false

      stripped.each_char do |char|
        if escape_next
          escape_next = false
          next
        end

        case char
        when '\\'
          escape_next = true if in_string
        when '"'
          in_string = !in_string
        when '{'
          unless in_string
            depth += 1
            count += 1 if depth == 1
          end
        when '}'
          depth -= 1 unless in_string
        end
      end

      count > 1
    end

    def initialize(@schema : Schema, @program_name : String = "cli")
      @subcommands = {} of String => Schema | CLI
      @default_subcommand = nil
      @subcommand_key = "subcommand"
      @completers = {} of String => Proc(Completion::Context, Array(String))
    end

    def initialize(@program_name : String)
      @schema = nil
      @subcommands = {} of String => Schema | CLI
      @default_subcommand = nil
      @subcommand_key = "subcommand"
      @completers = {} of String => Proc(Completion::Context, Array(String))
    end

    def subcommand(name : String, schema : Schema)
      @subcommands[name] = schema
    end

    def subcommand(name : String, cli : CLI)
      @subcommands[name] = cli
    end

    def subcommand(name : String, *, json : String)
      @subcommands[name] = Schema.from_json(json)
    end

    def subcommand(name : String, *, yaml : String)
      json = YAMLReader.parse(yaml).to_json
      @subcommands[name] = Schema.from_json(json)
    end

    # Load subcommand(s) from a file.
    # - Single-doc file: requires name, loads as single subcommand
    # - Multi-doc file without name: loads each doc as top-level subcommand
    # - Multi-doc file with name: loads docs as nested subcommands under name
    def subcommand(name : String, *, file : String)
      content = File.read(file)
      is_yaml = file.ends_with?(".yaml") || file.ends_with?(".yml")
      is_multi = is_yaml ? CLI.multi_yaml?(content) : CLI.multi_json?(content)

      if is_multi
        # Multi-doc with name: create nested CLI
        nested = CLI.new(name)
        if is_yaml
          nested.load_multi_yaml(content)
        else
          nested.load_multi_json(content)
        end
        @subcommands[name] = nested
      else
        # Single-doc: load as single subcommand
        schema = if is_yaml
                   json = YAMLReader.parse(content).to_json
                   Schema.from_json(json)
                 else
                   Schema.from_json(content)
                 end
        @subcommands[name] = schema
      end
    end

    # Load subcommands from a multi-document file (no parent name).
    # Each document must have a "name" field.
    def subcommand(*, file : String)
      content = File.read(file)
      is_yaml = file.ends_with?(".yaml") || file.ends_with?(".yml")
      is_multi = is_yaml ? CLI.multi_yaml?(content) : CLI.multi_json?(content)

      unless is_multi
        raise ArgumentError.new("Single-doc file requires a subcommand name: subcommand(\"name\", file: ...)")
      end

      if is_yaml
        load_multi_yaml(content)
      else
        load_multi_json(content)
      end
    end

    protected def load_multi_yaml(content : String)
      docs = YAMLReader.parse_all(content).map { |doc| JSON.parse(doc.to_json) }
      load_multi_docs(docs)
    end

    protected def load_multi_json(content : String)
      docs = [] of JSON::Any
      # Parse consecutive JSON objects (relaxed JSONL)
      remaining = content.strip
      while !remaining.empty?
        # Find the end of the current JSON object by tracking brace depth
        start_idx = remaining.index('{')
        break unless start_idx
        remaining = remaining[start_idx..]

        depth = 0
        in_string = false
        escape_next = false
        end_idx = 0

        remaining.each_char_with_index do |char, i|
          if escape_next
            escape_next = false
            next
          end

          case char
          when '\\'
            escape_next = true if in_string
          when '"'
            in_string = !in_string
          when '{'
            depth += 1 unless in_string
          when '}'
            depth -= 1 unless in_string
            if depth == 0
              end_idx = i
              break
            end
          end
        end

        json_str = remaining[0..end_idx]
        docs << JSON.parse(json_str)
        remaining = remaining[(end_idx + 1)..].strip
      end
      load_multi_docs(docs)
    end

    # Process multi-doc schemas with $id/$ref resolution
    protected def load_multi_docs(docs : Array(JSON::Any))
      # First pass: build registry of $id schemas (mixins)
      registry = {} of String => Hash(String, JSON::Any)
      subcommand_docs = [] of JSON::Any

      docs.each do |doc|
        hash = doc.as_h
        id = hash["$id"]?.try(&.as_s)
        name = hash["name"]?.try(&.as_s)

        if id && !name
          # Mixin: has $id but no name
          registry[id] = hash
        elsif name
          # Subcommand: has name
          subcommand_docs << doc
        else
          raise ArgumentError.new("Schema must have either 'name' (subcommand) or '$id' (mixin)")
        end
      end

      # Second pass: resolve refs and register subcommands
      subcommand_docs.each do |doc|
        hash = doc.as_h
        name = hash["name"].as_s
        resolved = resolve_all_of(hash, registry)
        @subcommands[name] = Schema.from_json_any(JSON.parse(resolved.to_json))
      end
    end

    # Resolve allOf with $ref, merging properties
    private def resolve_all_of(schema : Hash(String, JSON::Any), registry : Hash(String, Hash(String, JSON::Any))) : Hash(String, JSON::Any)
      all_of = schema["allOf"]?.try(&.as_a)
      return schema unless all_of

      merged = {} of String => JSON::Any

      all_of.each do |item|
        item_hash = item.as_h
        if ref = item_hash["$ref"]?.try(&.as_s)
          # Resolve reference
          referenced = registry[ref]?
          raise ArgumentError.new("Unknown $ref: #{ref}") unless referenced
          merge_schema(merged, referenced)
        else
          # Inline schema
          merge_schema(merged, item_hash)
        end
      end

      # Merge the subcommand's own keys (excluding allOf). The schema is one
      # more conjunct of the allOf, so `properties` and `required` combine
      # with the mixins' rather than replacing them; other keys override.
      schema.each do |key, value|
        next if key == "allOf"
        case key
        when "properties", "required"
          merge_schema(merged, {key => value})
        else
          merged[key] = value
        end
      end

      # Ensure type: object if properties exist
      if merged["properties"]? && !merged["type"]?
        merged["type"] = JSON::Any.new("object")
      end

      merged
    end

    # Merge source schema into target. Containers are copied, never aliased:
    # a mixin is merged into many subcommands, and mutating its `properties`
    # through one would leak that subcommand's options into the others.
    private def merge_schema(target : Hash(String, JSON::Any), source : Hash(String, JSON::Any))
      source.each do |key, value|
        next if key == "$id" # Don't copy $id to merged schema
        case key
        when "properties"
          target_props = target["properties"]?.try(&.as_h) || {} of String => JSON::Any
          value.as_h.each { |k, v| target_props[k] = v }
          target["properties"] = JSON::Any.new(target_props)
        when "required"
          required = target["required"]?.try(&.as_a) || [] of JSON::Any
          value.as_a.each { |v| required << v unless required.includes?(v) }
          target["required"] = JSON::Any.new(required)
        else
          target[key] = value unless target.has_key?(key)
        end
      end
    end

    # Set the subcommand used when arguments name none.
    def default_subcommand(name : String)
      @default_subcommand = name
    end

    # Set the JSON key that names the subcommand when parsing full JSON from
    # stdin (the `-@` form). Defaults to `"subcommand"`.
    def subcommand_key(key : String)
      @subcommand_key = key
    end

    # Control whether a bare `key=value` token — no leading dashes — may
    # implicitly assign to a named property. On by default. When off, such a
    # token is never read as an assignment: it falls to positional capture if a
    # slot is open, otherwise it is an unexpected argument. Turn it off for
    # deterministic parsing with zero implicit-assignment magic, e.g. when
    # operands legitimately contain `=` (`name=value` pairs passed through to
    # another tool) and you never want one silently absorbed as a property.
    # Note that a positional slot already captures `=`-bearing operands
    # literally regardless of this setting; the switch only governs the
    # implicit-assignment fallback. It does not affect `--flag=value`, which is
    # standard long-option syntax and always honored. Applies to this CLI and
    # its directly attached Schema subcommands; a nested CLI keeps its own
    # setting. (A colon is never an assignment separator: `key:value` is always
    # an ordinary token.)
    def bare_assignment(enabled : Bool)
      @bare_assignment = enabled
    end

    # Parse arguments into a `Result` (parsed data plus any validation errors);
    # never raises on invalid input. `defaults` seeds values not given on the
    # command line (e.g. from a config file), below CLI args and env vars.
    #
    # With subcommands, a mapping in `defaults` under a subcommand's name is
    # that subcommand's section, and any other key is global. A subcommand
    # takes the global keys it has an option for, then its section's keys
    # over them, every one of them. A nested CLI's section holds its own
    # subcommands' sections the same way.
    def parse(args : Array(String) = ARGV, *, defaults : Defaults? = nil) : Result
      parse(args, STDIN, defaults: defaults)
    end

    # :ditto: `input` supplies the stream read for the `-@` (stdin JSON) form.
    def parse(args : Array(String), input : IO, *, defaults : Defaults? = nil) : Result
      parse_scoped(args, input, {} of String => JSON::Any, defaults_hash(defaults))
    end

    # Parse with the defaults split as `parse` describes: `globals`, those
    # from further up, and `section`, the ones given for this CLI.
    # The JSON form, given an outer CLI's JSON for this one: the subcommand's
    # name in it if this CLI has subcommands, its options if not.
    protected def parse_json_scoped(input : IO, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Result
      if !@subcommands.empty?
        parse_from_stdin_full(input, globals, section)
      elsif schema = @schema
        parse_from_stdin_args(input, schema, command_defaults(schema, globals, section))
      else
        raise ArgumentError.new("CLI has no schema and no subcommands defined")
      end
    end

    protected def parse_scoped(args : Array(String), input : IO, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Result
      if !@subcommands.empty?
        parse_with_subcommands(args, input, globals, section)
      elsif schema = @schema
        parse_flat(args, schema, input, nil, command_defaults(schema, globals, section))
      else
        raise ArgumentError.new("CLI has no schema and no subcommands defined")
      end
    end

    # Parse and return just the data, raising `ParseError` on validation errors.
    # Use when you want the values directly and treat invalid input as fatal.
    def json(args : Array(String) = ARGV, *, defaults : Defaults? = nil) : JSON::Any
      json(args, STDIN, defaults: defaults)
    end

    def json(args : Array(String), input : IO, *, defaults : Defaults? = nil) : JSON::Any
      result = parse(args, input, defaults: defaults)
      raise ParseError.new(result.errors) unless result.valid?
      result.data
    end

    # Run the CLI with automatic --help, --completions, and error handling.
    # Prints help/completions and exits 0, prints errors and exits 1, otherwise returns/yields result.
    def run(args : Array(String) = ARGV, *, defaults : Defaults? = nil) : Result
      run(args, STDIN, defaults: defaults)
    end

    def run(args : Array(String) = ARGV, *, defaults : Defaults? = nil, &) : Nil
      run(args, STDIN, defaults: defaults) { |r| yield r }
    end

    def run(args : Array(String), input : IO, *, defaults : Defaults? = nil) : Result
      handle_completion(args)
      result = parse(args, input, defaults: defaults)
      handle_run_result(result)
      result
    end

    def run(args : Array(String), input : IO, *, defaults : Defaults? = nil, &) : Nil
      handle_completion(args)
      result = parse(args, input, defaults: defaults)
      handle_run_result(result)
      yield result
    end

    private def handle_run_result(result : Result) : Nil
      if result.help_requested?
        if subcmd = result.help_subcommand
          @output.puts help(subcmd)
        else
          @output.puts help
        end
        exit 0
      end

      if result.completion_requested?
        case result.completion_shell
        when "bash" then @output.puts bash_completion
        when "zsh"  then @output.puts zsh_completion
        when "fish" then @output.puts fish_completion
        end
        exit 0
      end

      unless result.valid?
        STDERR.puts result.errors.join("\n")
        exit 1
      end
    end

    private def parse_with_subcommands(args : Array(String), input : IO, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Result
      # "xerp -@": JSON naming the subcommand
      return parse_from_stdin_full(input, globals, section) if args == [STDIN_JSON]

      # Check for top-level help (--help/-h before any subcommand)
      return Result.new({} of String => JSON::Any, [] of String, nil, true, nil) if help_flag?(args.first?)

      # Check for --completions
      if result = check_completions_flag(args)
        return result
      end

      # Check if first arg matches a known subcommand (supports abbreviations)
      if (first = args.first?) && (resolved_name = resolve_subcommand(first)) && (subcmd = @subcommands[resolved_name]?)
        return dispatch_subcommand(subcmd, resolved_name, args[1..], input, globals, section)
      end

      # Fall back to default subcommand if set
      if (default = @default_subcommand) && (subcmd = @subcommands[default]?)
        return dispatch_subcommand(subcmd, default, args, input, globals, section)
      end

      # No match and no default
      error = args.empty? ? "No subcommand specified" : "Unknown subcommand: #{args[0]}"
      Result.new({} of String => JSON::Any, [error])
    end

    private def help_flag?(arg : String?) : Bool
      arg == "--help" || arg == "-h"
    end

    private def dispatch_subcommand(subcmd : Schema | CLI, subcmd_name : String, args : Array(String), input : IO, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Result
      globals, section = subcommand_defaults(subcmd_name, globals, section)
      case subcmd
      when CLI
        result = subcmd.parse_scoped(args, input, globals, section)
        full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
        if result.help_requested?
          help_subcmd = result.help_subcommand ? "#{subcmd_name} #{result.help_subcommand}" : subcmd_name
          return Result.new(result.data, result.errors, full_subcmd, true, help_subcmd)
        end
        Result.new(result.data, result.errors, full_subcmd)
      when Schema
        result = parse_flat(args, subcmd, input, subcmd_name, command_defaults(subcmd, globals, section))
        if result.help_requested?
          return Result.new(result.data, result.errors, subcmd_name, true, subcmd_name)
        end
        Result.new(result.data, result.errors, subcmd_name)
      else
        Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
      end
    end

    private def check_completions_flag(args : Array(String)) : Result?
      return unless args.size >= 2 && args[0] == "--completions"
      shell = args[1]
      if shell.in?("bash", "zsh", "fish")
        Result.new({} of String => JSON::Any, [] of String, nil, false, nil, shell)
      else
        Result.new({} of String => JSON::Any, ["Unknown shell '#{shell}'. Supported: bash, zsh, fish"])
      end
    end

    private def parse_from_stdin_full(input : IO, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Result
      json_str = input.gets_to_end
      json = JSON.parse(json_str)
      data = json.as_h? || {} of String => JSON::Any

      # Extract subcommand from JSON using configured key
      subcmd_name = data.delete(@subcommand_key).try(&.as_s?)

      # Determine which subcommand to use
      subcmd_name ||= @default_subcommand

      unless subcmd_name
        return Result.new({} of String => JSON::Any, ["No '#{@subcommand_key}' specified in JSON"])
      end

      # Resolve abbreviated subcommand name
      resolved_name = resolve_subcommand(subcmd_name)
      unless resolved_name && (subcmd = @subcommands[resolved_name]?)
        return Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
      end
      subcmd_name = resolved_name
      globals, section = subcommand_defaults(subcmd_name, globals, section)

      case subcmd
      when CLI
        # A nested CLI reads the rest of the JSON as its own.
        nested_input = IO::Memory.new(data.to_json)
        result = subcmd.parse_json_scoped(nested_input, globals, section)
        full_subcmd = result.subcommand ? "#{subcmd_name} #{result.subcommand}" : subcmd_name
        return Result.new(result.data, result.errors, full_subcmd)
      when Schema
        errors = [] of String
        apply_env_vars(data, errors, subcmd)
        apply_user_defaults(data, command_defaults(subcmd, globals, section))
        apply_defaults(data, subcmd)
        errors.concat(Validator.validate(data, subcmd))
        return Result.new(data, errors, subcmd_name)
      end

      Result.new({} of String => JSON::Any, ["Unknown subcommand: #{subcmd_name}"])
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_from_stdin_args(input : IO, schema : Schema, defaults : Hash(String, JSON::Any)) : Result
      json_str = input.gets_to_end
      json = JSON.parse(json_str)
      data = json.as_h? || {} of String => JSON::Any

      errors = [] of String
      apply_env_vars(data, errors, schema)
      apply_user_defaults(data, defaults)
      apply_defaults(data, schema)
      errors.concat(Validator.validate(data, schema))

      Result.new(data, errors)
    rescue ex : JSON::ParseException
      Result.new({} of String => JSON::Any, ["Invalid JSON from stdin: #{ex.message}"])
    end

    private def parse_flat(args : Array(String), schema : Schema, input : IO, subcommand_path : String?, defaults : Hash(String, JSON::Any)) : Result
      # "xerp mark -@": JSON options for this schema, unless the schema
      # claims -@ for an option of its own, as it may -h.
      if args == [STDIN_JSON] && !build_short_map(schema).has_key?("@")
        return parse_from_stdin_args(input, schema, defaults)
      end

      # Check for help flags early
      help_requested, _ = any_help_requested?(args, schema)
      return Result.new({} of String => JSON::Any, [] of String, nil, true, subcommand_path) if help_requested

      # Check for --completions (only at top level, not within subcommands)
      if subcommand_path.nil? && (result = check_completions_flag(args))
        return result
      end

      data = {} of String => JSON::Any
      errors = [] of String
      positional_names = schema.positional

      positional_index = consume_tokens(args, schema, data, errors, positional_names)

      # Initialize unfilled variadic positionals to empty arrays
      init_empty_variadic(positional_index, positional_names, data, errors, schema)

      # Apply environment variables - CLI args take precedence
      apply_env_vars(data, errors, schema)
      # Before defaults fill anything in, every value came from a token.
      unconverted = unconverted_fields(data, resolve_property(schema.root, schema), schema)

      # Apply user-provided defaults (e.g., from config file) - CLI and env vars take precedence
      apply_user_defaults(data, defaults)

      apply_defaults(data, schema)
      errors.concat(Validator.validate(data, schema, unconverted))

      Result.new(data, errors)
    end

    # Walk the argument tokens, filling `data`/`errors`. Returns the number of
    # positional slots consumed (for variadic initialization).
    private def consume_tokens(args : Array(String), schema : Schema, data : Hash(String, JSON::Any), errors : Array(String), positional_names : Array(String)) : Int32
      short_to_long = build_short_map(schema)
      positional_index = 0
      options_ended = false
      i = 0

      while i < args.size
        arg = args[i]

        if !options_ended && arg == "--"
          # POSIX end-of-options: everything after is treated as a positional,
          # even if it looks like a flag. The marker itself is discarded.
          options_ended = true
          i += 1
        elsif !options_ended && short_flag?(arg)
          i += handle_short_flag(arg, args, i, data, errors, short_to_long, schema)
        elsif !options_ended && flag?(arg)
          i += handle_long_flag(arg, args, i, data, errors, schema)
        elsif positional_index < positional_names.size
          consumed, pos_advance = handle_positional(arg, args, i, positional_index, positional_names, data, errors, schema, options_ended)
          i += consumed
          positional_index += pos_advance
        else
          i += handle_extra_arg(arg, args, i, data, errors, schema)
        end
      end

      positional_index
    end

    private def flag?(arg : String) : Bool
      arg.starts_with?("--")
    end

    private def short_flag?(arg : String) : Bool
      return false unless arg.starts_with?("-") && arg.size > 1
      return false if arg.starts_with?("--")
      # A token like -50 or -3.14 is a negative number (a value), not a short
      # flag. Mirrors the same exemption flag_like? already applies to values.
      !arg[1].ascii_number?
    end

    private def handle_short_flag(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Int32
      short_keys = arg[1..]
      if short_keys.size == 1
        handle_single_short_flag(short_keys, args, i, data, errors, short_to_long, schema)
      else
        handle_combined_short_flags(arg, short_keys, args, i, data, errors, short_to_long, schema)
      end
    end

    private def handle_single_short_flag(short_keys : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Int32
      if long_key = short_to_long[short_keys]?
        key, value, consumed, coerce_error = parse_long_flag("--#{long_key}", args, i, schema)
        if key
          errors << coerce_error if coerce_error
          set_option_value(data, key, value, errors, schema)
        end
        consumed
      elsif short_keys == "@"
        errors << "'#{STDIN_JSON}' reads options as JSON from stdin, and takes no other arguments"
        1
      else
        errors << unknown_option_error(short_keys, short_to_long.keys, "-")
        1
      end
    end

    # A cluster of short flags, read as getopt reads one: each letter is a
    # flag until one that takes a value, which takes the rest of the cluster
    # (`-w80`, `-lw80`), or the next argument when it ends the cluster
    # (`-lw 80`). Returns the number of arguments consumed.
    private def handle_combined_short_flags(arg : String, short_keys : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), short_to_long : Hash(String, String), schema : Schema) : Int32
      short_keys.each_char_with_index do |c, n|
        char_str = c.to_s
        unless long_key = short_to_long[char_str]?
          errors << unknown_option_error(char_str, short_to_long.keys, "-", "in '#{arg}'")
          return 1
        end
        if boolean_property?(long_key, schema)
          set_nested_value(data, long_key, JSON::Any.new(true), errors)
          next
        end

        rest = short_keys[(n + 1)..]
        return handle_single_short_flag(char_str, args, i, data, errors, short_to_long, schema) if rest.empty?
        coerced, coerce_error = coerce_value(long_key, rest, schema)
        errors << coerce_error if coerce_error
        set_option_value(data, long_key, coerced, errors, schema)
        return 1
      end
      1
    end

    private def handle_long_flag(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Int32
      key, value, consumed, coerce_error = parse_long_flag(arg, args, i, schema)
      if key
        errors << coerce_error if coerce_error
        set_option_value(data, key, value, errors, schema)
      else
        opt_name = arg.split("=", 2)[0][2..]
        errors << unknown_option_error(opt_name, available_options(schema))
      end
      consumed
    end

    private def handle_positional(arg : String, args : Array(String), i : Int32, positional_index : Int32, positional_names : Array(String), data : Hash(String, JSON::Any), errors : Array(String), schema : Schema, options_ended : Bool = false) : {Int32, Int32}
      key = positional_names[positional_index]
      prop = find_property(key, schema)

      if prop.try(&.type) == Property::Type::Array && positional_index == positional_names.size - 1
        consumed = collect_variadic(args, i, key, data, errors, schema, options_ended)
        {consumed, 1}
      else
        coerced, coerce_error = coerce_value(key, arg, schema)
        errors << coerce_error if coerce_error
        set_nested_value(data, key, coerced, errors)
        {1, 1}
      end
    end

    private def collect_variadic(args : Array(String), start : Int32, key : String, data : Hash(String, JSON::Any), errors : Array(String), schema : Schema, passthrough : Bool = false) : Int32
      prop = find_property(key, schema)
      item_type = prop.try(&.items).try(&.type)
      items = [] of JSON::Any
      i = start
      while i < args.size
        current_arg = args[i]
        # A variadic positional is greedy: it captures every token literally,
        # including ones that contain `:`/`=` (e.g. Expenses:Food, host:8080) or
        # look like negative numbers (-50). It stops only at a genuine flag so
        # that flag can be parsed normally. After `--` even flags are captured.
        break if !passthrough && flag_like?(current_arg)
        array_pieces(current_arg, prop).each do |piece|
          coerced, coerce_error = coerce_scalar(key, piece, item_type)
          errors << coerce_error if coerce_error
          items << coerced
        end
        i += 1
      end
      set_nested_value(data, key, JSON::Any.new(items), errors)
      i - start
    end

    private def init_empty_variadic(positional_index : Int32, positional_names : Array(String), data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Nil
      return unless positional_index < positional_names.size
      key = positional_names[positional_names.size - 1]
      prop = find_property(key, schema)
      if prop.try(&.type) == Property::Type::Array && !data.has_key?(key)
        set_nested_value(data, key, JSON::Any.new([] of JSON::Any), errors)
      end
    end

    private def handle_extra_arg(arg : String, args : Array(String), i : Int32, data : Hash(String, JSON::Any), errors : Array(String), schema : Schema) : Int32
      key, value, consumed, coerce_error = parse_argument(arg, args, i, schema)
      if key
        errors << coerce_error if coerce_error
        set_option_value(data, key, value, errors, schema)
      elsif bare_assignment? && arg.includes?("=")
        # Looks like an assignment to an unknown property — suggest a fix.
        unknown_key = arg.split("=", 2)[0]
        errors << unknown_option_error(unknown_key, available_options(schema), "")
      else
        errors << "Unexpected argument '#{arg}'"
      end
      consumed
    end

    private def build_short_map(schema : Schema) : Hash(String, String)
      map = {} of String => String
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.each do |name, prop|
          if short = prop.short
            map[short] = name
          end
        end
      end
      map
    end

    private def parse_long_flag(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32, String?}
      key = arg[2..]
      base_key = key.includes?("=") ? key.split("=", 2)[0] : key

      # Validate that the option exists in the schema
      unless property_exists?(base_key, schema)
        return {nil, nil, 1, nil}
      end

      is_boolean = boolean_property?(key, schema)

      if key.includes?("=")
        parts = key.split("=", 2)
        coerced, error = coerce_value(parts[0], parts[1], schema)
        {parts[0], coerced, 1, error}
      elsif is_boolean
        # Check if next arg is a boolean value (--flag true/false)
        if index + 1 < args.size && boolean_value?(args[index + 1])
          coerced, error = coerce_value(key, args[index + 1], schema)
          {key, coerced, 2, error}
        else
          # No value or non-boolean next arg - treat as flag (true)
          {key, JSON::Any.new(true), 1, nil}
        end
      elsif index + 1 < args.size && !flag_like?(args[index + 1])
        # Non-boolean with a value (allows negative numbers)
        coerced, error = coerce_value(key, args[index + 1], schema)
        {key, coerced, 2, error}
      else
        # Non-boolean without a value - error
        {key, nil, 1, "Missing value for --#{key}"}
      end
    end

    # Check if a string is a boolean value
    private def boolean_value?(arg : String) : Bool
      arg.downcase.in?("true", "false", "yes", "no", "on", "off", "1", "0")
    end

    # Check if arg looks like a flag: one that starts with -, but not a
    # negative number (-5, -3.14) or a lone -, which by convention names
    # standard input or output as a file.
    private def flag_like?(arg : String) : Bool
      return false unless arg.starts_with?("-") && arg.size > 1
      !arg[1].ascii_number?
    end

    # Validate data against a schema, returning any errors.
    # If no schema is provided, uses the CLI's root schema.
    # For subcommand validation, pass the subcommand name (space-separated for nested).
    def validate(data : Hash(String, JSON::Any), subcommand : String? = nil) : Array(String)
      if cmd = subcommand
        parts = cmd.split(" ", 2)
        subcmd = @subcommands[parts[0]]? || raise ArgumentError.new("Unknown subcommand: #{parts[0]}")
        case subcmd
        when CLI
          # Delegate to nested CLI with remaining subcommand path
          return subcmd.validate(data, parts[1]?)
        when Schema
          return Validator.validate(data, subcmd)
        end
        [] of String
      else
        schema = @schema || raise ArgumentError.new("No schema available")
        Validator.validate(data, schema)
      end
    end

    # :ditto: Validate a previously parsed `Result` against its subcommand.
    def validate(result : Result) : Array(String)
      validate(result.data.as_h, result.subcommand)
    end

    # Generate a shell completion shim. By default it calls back into this
    # program; pass `command:` to point completion at a separate (e.g. lighter)
    # binary that answers the hidden `__complete` verb.
    def bash_completion(command : String = @program_name) : String
      Completion.new(self).bash(command)
    end

    # :ditto:
    def zsh_completion(command : String = @program_name) : String
      Completion.new(self).zsh(command)
    end

    # :ditto:
    def fish_completion(command : String = @program_name) : String
      Completion.new(self).fish(command)
    end

    # Register a dynamic completer for a field, identified by its dotted path:
    # the field name for a flat CLI, or `subcommand.field` (`a.b.field` when
    # nested). The block receives a Completion::Context and returns the
    # candidate strings. Raises if the path does not match a schema field, so
    # typos and renames fail fast.
    def completer(path : String, &block : Completion::Context -> Array(String))
      schema = resolve_completer_schema(path)
      field = path.split(".").last
      unless schema && (props = schema.root.properties) && props.has_key?(field)
        raise ArgumentError.new("completer path '#{path}' does not match any field in the schema")
      end
      @completers[path] = block
    end

    private def resolve_completer_schema(path : String) : Schema?
      parts = path.split(".")
      subcommand_path = parts[0...-1]
      return @schema if subcommand_path.empty?

      cli = self
      parts_schema : Schema? = nil
      subcommand_path.each do |name|
        case sub = cli.subcommands[name]?
        when CLI    then cli = sub
        when Schema then parts_schema = sub
        else             return
        end
      end
      parts_schema || cli.schema
    end

    # If this invocation is a completion request (the hidden `__complete`
    # verb), print candidates and — unless `exit_process: false` — exit 0.
    # Returns true when it handled completion, false otherwise, so it can be
    # called early in a program (before heavy initialization) or as the whole
    # body of a dedicated completion helper binary. The developer never types
    # the verb itself; the generated shim supplies it.
    def handle_completion(args : Array(String) = ARGV, *, io : IO = @output, exit_process : Bool = true) : Bool
      return false unless args.first? == Completion::COMPLETE_VERB

      rest = args[1..]
      cword = rest[0]?.try(&.to_i?) || 0
      words = rest.size > 1 ? rest[1..] : [] of String
      Completion.new(self).candidates(words, cword).each { |candidate| io.puts(candidate) }

      exit 0 if exit_process
      true
    end

    private def parse_argument(arg : String, args : Array(String), index : Int32, schema : Schema) : {String?, JSON::Any?, Int32, String?}
      # Support key=value style, unless bare assignment is off.
      return {nil, nil, 1, nil} unless bare_assignment? && arg.includes?("=")

      parts = arg.split("=", 2)
      key = parts[0]
      return {nil, nil, 1, nil} unless property_exists?(key, schema)

      coerced, error = coerce_value(key, parts[1], schema)
      {key, coerced, 1, error}
    end

    private def boolean_property?(key : String, schema : Schema) : Bool
      prop = find_property(key, schema)
      prop.try(&.type.boolean?) || false
    end

    private def property_exists?(key : String, schema : Schema) : Bool
      !find_property(key, schema).nil?
    end

    private def available_options(schema : Schema) : Array(String)
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.keys
      else
        [] of String
      end
    end

    # Look up a property by dotted path (e.g. "server.port"), descending through
    # object properties and resolving `$ref`s. Returns nil if any segment is
    # missing or a non-final segment isn't an object.
    private def find_property(key : String, schema : Schema) : Property?
      parts = key.split(".")
      current = resolve_property(schema.root, schema)

      parts.each_with_index do |part, i|
        if props = current.properties
          if prop = props[part]?
            resolved = resolve_property(prop, schema)
            if i == parts.size - 1
              return resolved
            elsif resolved.type.object?
              current = resolved
            else
              return
            end
          else
            return
          end
        else
          return
        end
      end

      nil
    end

    private def resolve_property(prop : Property, schema : Schema) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end

    # The fields whose value didn't convert to the field's type. A token is a
    # string, and converting one leaves a string in a number or boolean field
    # only when it fails, which it reports; validating the value as well
    # would report the same mistake again. So this runs on values that came
    # from tokens alone, before defaults are filled in.
    private def unconverted_fields(data : Hash(String, JSON::Any), parent : Property, schema : Schema, prefix : String = "", fields : Set(String) = Set(String).new) : Set(String)
      return fields unless props = parent.properties
      data.each do |name, value|
        next unless prop = props[name]?
        prop = resolve_property(prop, schema)
        path = prefix.empty? ? name : "#{prefix}.#{name}"
        if converted_type?(prop.type) && value.as_s?
          fields << path
        elsif prop.type.array? && (items = prop.items) && converted_type?(resolve_property(items, schema).type) && value.as_a?.try(&.any?(&.as_s?))
          fields << path
        elsif nested = value.as_h?
          unconverted_fields(nested, prop, schema, path, fields)
        end
      end
      fields
    end

    private def converted_type?(type : Property::Type) : Bool
      type.integer? || type.number? || type.boolean?
    end

    private def coerce_value(key : String, value : String, schema : Schema) : {JSON::Any, String?}
      prop = find_property(key, schema)
      type = prop.try(&.type)

      case type
      when Property::Type::Integer, Property::Type::Number, Property::Type::Boolean
        coerce_scalar(key, value, type)
      when Property::Type::Array
        # The value is one item, or several when the property names
        # separators. Coerce each to the array's `items` type, as a variadic
        # positional does; report the first item that doesn't fit.
        item_type = prop.try(&.items).try(&.type)
        first_error = nil
        items = array_pieces(value, prop).map do |v|
          coerced, error = coerce_scalar(key, v, item_type)
          first_error ||= error
          coerced
        end
        {JSON::Any.new(items), first_error}
      else
        # Expand ~ for path format
        if prop.try(&.format) == "path"
          expanded = expand_tilde(value)
          {JSON::Any.new(expanded), nil}
        else
          {JSON::Any.new(value), nil}
        end
      end
    end

    # The items a word gives an array: the word itself, or its pieces when the
    # property names separators.
    private def array_pieces(value : String, prop : Property?) : Array(String)
      if separators = prop.try(&.separator)
        Property.split(value, separators)
      else
        [value]
      end
    end

    # Coerce a single string token to a scalar type (integer/number/boolean).
    # Any other type (or nil) passes the value through unchanged as a string.
    # Returns the value plus an error message when the token doesn't fit.
    private def coerce_scalar(key : String, value : String, type : Property::Type?) : {JSON::Any, String?}
      case type
      when Property::Type::Integer
        if int_val = value.to_i64?(strict: true)
          {JSON::Any.new(int_val), nil}
        else
          {JSON::Any.new(value), "Invalid integer value '#{value}' for #{key}"}
        end
      when Property::Type::Number
        # JSON has no infinities or NaN, which to_f64? reads.
        if (float_val = value.to_f64?(strict: true)) && float_val.finite?
          {JSON::Any.new(float_val), nil}
        else
          {JSON::Any.new(value), "Invalid number value '#{value}' for #{key}"}
        end
      when Property::Type::Boolean
        case value.downcase
        when "true", "1", "yes", "on"  then {JSON::Any.new(true), nil}
        when "false", "0", "no", "off" then {JSON::Any.new(false), nil}
        else                                {JSON::Any.new(value), "Invalid boolean value '#{value}' for #{key}. Use: true/false, yes/no, on/off, 1/0"}
        end
      else
        {JSON::Any.new(value), nil}
      end
    end

    private def expand_tilde(path : String) : String
      if path == "~"
        Path.home.to_s
      elsif path.starts_with?("~/")
        Path.home.to_s + path[1..]
      else
        path
      end
    end

    # Store a value under a dotted key, building intermediate objects as needed
    # (e.g. "server.port" => {"server" => {"port" => ...}}). A nil value is a
    # no-op; a non-object value blocking the path records an error.
    # Store an option's value. An array option given more than once collects
    # the items of each (`-I a -I b`), as getopt programs do; any other
    # option keeps the last value given.
    private def set_option_value(data : Hash(String, JSON::Any), key : String, value : JSON::Any?, errors : Array(String), schema : Schema)
      if value && (items = value.as_a?) && (earlier = nested_value(data, key).try(&.as_a?)) &&
         find_property(key, schema).try(&.type) == Property::Type::Array
        value = JSON::Any.new(earlier + items)
      end
      set_nested_value(data, key, value, errors)
    end

    private def nested_value(data : Hash(String, JSON::Any), key : String) : JSON::Any?
      parts = key.split(".")
      current = data
      parts[0..-2].each do |part|
        current = current[part]?.try(&.as_h?) || return
      end
      current[parts.last]?
    end

    private def set_nested_value(data : Hash(String, JSON::Any), key : String, value : JSON::Any?, errors : Array(String))
      return unless value

      parts = key.split(".")

      if parts.size == 1
        data[key] = value
      else
        current = data
        parts[0..-2].each do |part|
          unless current[part]?
            current[part] = JSON::Any.new({} of String => JSON::Any)
          end
          if current[part].as_h?
            current = current[part].as_h
          else
            errors << "Cannot set nested property #{key}: #{part} is not an object"
            return
          end
        end
        current[parts.last] = value
      end
    end

    private def apply_env_vars(data : Hash(String, JSON::Any), errors : Array(String), schema : Schema)
      root = resolve_property(schema.root, schema)
      return unless props = root.properties

      props.each do |name, prop|
        resolved_prop = resolve_property(prop, schema)
        next if data.has_key?(name) # CLI arg takes precedence
        next unless env_var = resolved_prop.env
        next unless env_value = ENV[env_var]?

        coerced, coerce_error = coerce_value(name, env_value, schema)
        errors << coerce_error if coerce_error
        data[name] = coerced
      end
    end

    private def apply_user_defaults(data : Hash(String, JSON::Any), defaults : Hash(String, JSON::Any))
      fill_user_defaults(data, defaults)
    end

    private def defaults_hash(defaults : Defaults?) : Hash(String, JSON::Any)
      return {} of String => JSON::Any unless defaults
      hash = defaults.is_a?(JSON::Any) ? defaults.as_h? : defaults
      hash || raise ArgumentError.new("defaults must be a JSON object")
    end

    # Split this CLI's `section` of the defaults for subcommand `name`: the
    # keys that aren't a subcommand's section are global, over the `globals`
    # from further up, and `name`'s section is the subcommand's own.
    private def subcommand_defaults(name : String, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : {Hash(String, JSON::Any), Hash(String, JSON::Any)}
      own = section.reject { |key, value| @subcommands.has_key?(key) && value.as_h? }
      unless own.empty?
        globals = globals.clone
        deep_merge!(globals, own)
      end
      {globals, section[name]?.try(&.as_h?) || {} of String => JSON::Any}
    end

    # The defaults a command takes: the global ones it has an option for,
    # then its section's, all of them, as a CLI without subcommands takes
    # all of its defaults.
    private def command_defaults(schema : Schema, globals : Hash(String, JSON::Any), section : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      props = resolve_property(schema.root, schema).properties
      defaults = globals.select { |key, _| props.try(&.has_key?(key)) }
      return section if defaults.empty?
      defaults = defaults.clone
      deep_merge!(defaults, section)
      defaults
    end

    # Fill keys missing from `data`, recursing into objects present on both
    # sides so `--server.port 1` keeps a config-supplied `server.host`. Values
    # are cloned: parsing must never mutate the caller's defaults.
    private def fill_user_defaults(data : Hash(String, JSON::Any), defaults : Hash(String, JSON::Any))
      defaults.each do |key, value|
        if existing = data[key]?
          if (existing_hash = existing.as_h?) && (default_hash = value.as_h?)
            fill_user_defaults(existing_hash, default_hash)
          end
        else
          data[key] = value.clone
        end
      end
    end

    private def apply_defaults(data : Hash(String, JSON::Any), schema : Schema)
      root = resolve_property(schema.root, schema)
      return unless props = root.properties

      props.each do |name, prop|
        apply_property_defaults(data, name, prop, schema)
      end
    end

    # `expanding` holds the `$ref`s being descended through on this path. A
    # default on a ref already in it belongs to a recursive (tree-shaped)
    # schema and would nest copies of itself forever, so it is skipped; data
    # the user supplied is still descended, which terminates with the data.
    private def apply_property_defaults(data : Hash(String, JSON::Any), name : String, prop : Property, schema : Schema, expanding : Set(String) = Set(String).new)
      ref = prop.ref
      recursive = ref ? expanding.includes?(ref) : false
      prop = resolve_property(prop, schema)

      unless data.has_key?(name) || recursive
        if default = prop.default
          data[name] = default.clone # never alias the schema's default into results
        end
      end

      if prop.type.object? && (nested_props = prop.properties)
        if nested_data = data[name]?.try(&.as_h?)
          inner = ref ? expanding | Set{ref} : expanding
          nested_props.each do |nested_name, nested_prop|
            apply_property_defaults(nested_data, nested_name, nested_prop, schema, inner)
          end
        end
      end
    end

    # Find best suggestion for a typo using Levenshtein distance
    # Returns nil if no good match found (distance > 2 or > 30% of length)
    private def find_suggestion(input : String, candidates : Array(String)) : String?
      return if candidates.empty?
      return if input.size < 2 # Don't suggest for single-character inputs

      best_match : String? = nil
      best_distance = Int32::MAX

      candidates.each do |candidate|
        # Distance is at least the length difference, so skip candidates that
        # can't qualify before paying for the O(n*m) comparison.
        next if (input.size - candidate.size).abs > 2
        distance = levenshtein_distance(input, candidate)
        max_len = Math.max(input.size, candidate.size)
        max_allowed = (max_len * 0.3).to_i

        if distance <= 2 && distance <= max_allowed && distance < best_distance
          best_distance = distance
          best_match = candidate
        end
      end

      best_match
    end

    # Generate error message for unknown option with suggestion support
    private def unknown_option_error(input : String, candidates : Array(String), prefix : String = "--", context : String? = nil) : String
      display = "#{prefix}#{input}"
      ctx = context ? " #{context}" : ""

      if candidates.empty?
        "Unknown option '#{display}'#{ctx}: no #{prefix == "-" ? "short flags" : "options"} defined"
      elsif suggestion = find_suggestion(input, candidates)
        "Unknown option '#{display}'#{ctx}. Did you mean '#{prefix}#{suggestion}'?"
      else
        formatted = candidates.map { |c| "#{prefix}#{c}" }.join(", ")
        "Unknown option '#{display}'#{ctx}. Available: #{formatted}"
      end
    end

    # Levenshtein distance between two strings
    private def levenshtein_distance(s1 : String, s2 : String) : Int32
      return s2.size if s1.empty?
      return s1.size if s2.empty?

      # Use two-row optimization for space efficiency
      prev_row = Array.new(s2.size + 1) { |i| i }
      curr_row = Array.new(s2.size + 1, 0)

      s1.each_char.with_index do |c1, i|
        curr_row[0] = i + 1

        s2.each_char.with_index do |c2, j|
          cost = c1 == c2 ? 0 : 1
          curr_row[j + 1] = Math.min(
            curr_row[j] + 1, # insertion
            Math.min(
            prev_row[j + 1] + 1, # deletion
            prev_row[j] + cost   # substitution
          )
          )
        end

        prev_row, curr_row = curr_row, prev_row
      end

      prev_row[s2.size]
    end

    # Resolve abbreviated subcommand name to full name
    # Returns nil if no match, ambiguous, or too short (< 3 chars for non-exact)
    protected def resolve_subcommand(input : String) : String?
      return input if @subcommands.has_key?(input) # Exact match
      return if input.size < 3                     # Too short for abbreviation

      matches = @subcommands.keys.select(&.starts_with?(input))
      matches.size == 1 ? matches.first : nil # Unambiguous only
    end
  end
end
