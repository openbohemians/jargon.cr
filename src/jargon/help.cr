module Jargon
  class CLI
    # Render the program's help text: a command listing when subcommands are
    # defined, an option listing for a flat CLI, or a bare usage line otherwise.
    def help : String
      help_as(program_name)
    end

    # Render help for a single subcommand. `subcommand` is space-separated for
    # nested commands (e.g. `"remote add"`). Raises `ArgumentError` for a
    # subcommand the CLI doesn't have, as `validate` does.
    def help(subcommand : String) : String
      subcommand_help_as(program_name, subcommand)
    end

    # The help, with `command` (the program's name, followed by the
    # subcommands leading to this CLI when it is nested) in its usage lines.
    protected def help_as(command : String) : String
      if !@subcommands.empty?
        help_with_subcommands(command)
      elsif s = @schema
        build_help_text(s, command)
      else
        "Usage: #{command} <command> [options]"
      end
    end

    protected def subcommand_help_as(command : String, subcommand : String) : String
      parts = subcommand.split(" ", 2)
      subcmd_name = parts[0]
      subcmd_command = "#{command} #{subcmd_name}"

      case subcmd = @subcommands[subcmd_name]?
      when CLI
        parts.size > 1 ? subcmd.subcommand_help_as(subcmd_command, parts[1]) : subcmd.help_as(subcmd_command)
      when Schema
        build_help_text(subcmd, subcmd_command)
      else
        raise ArgumentError.new("Unknown subcommand: #{subcmd_name}")
      end
    end

    private def help_with_subcommands(command : String) : String
      lines = ["Usage: #{command} <command> [options]", "", "Commands:"]

      width = @subcommands.keys.max_of?(&.size) || 0
      @subcommands.each do |name, subcmd|
        case subcmd
        when Schema
          help_entry(lines, "  #{name}", width + 4, subcmd.root.description)
        when CLI
          # A nested CLI is a group with no description of its own; list its
          # children indented, each aligned within their own column.
          help_entry(lines, "  #{name}", width + 4, nil)
          sub_width = subcmd.subcommands.keys.max_of?(&.size) || 0
          subcmd.subcommands.each do |sub_name, sub|
            description = sub.is_a?(Schema) ? sub.root.description : nil
            help_entry(lines, "    #{sub_name}", sub_width + 6, description)
          end
        end
      end

      lines << ""
      lines << "Run '#{command} <command> --help' for command-specific options."
      lines.join("\n")
    end

    private def user_defined_help?(schema : Schema) : Bool
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.has_key?("help")
      else
        false
      end
    end

    private def user_defined_h_short?(schema : Schema) : Bool
      root = resolve_property(schema.root, schema)
      if props = root.properties
        props.values.any? { |prop| prop.short == "h" }
      else
        false
      end
    end

    # Scan args for an auto-help flag, returning {requested?, index}. A schema
    # may claim `--help`/`-h` for itself (a `help` property or a property with
    # short `h`); when it does, the flag belongs to the user's schema and does
    # not trigger Jargon's built-in help, so we report {false, -1}. Scanning
    # stops at a POSIX `--`: anything after it is a literal operand.
    private def any_help_requested?(args : Array(String), schema : Schema?) : {Bool, Int32}
      args.each_with_index do |arg, i|
        break if arg == "--"
        if arg == "--help"
          if schema && user_defined_help?(schema)
            return {false, -1}
          end
          return {true, i}
        elsif arg == "-h"
          if schema && user_defined_h_short?(schema)
            return {false, -1}
          end
          return {true, i}
        end
      end
      {false, -1}
    end

    private def build_help_text(schema : Schema, command : String) : String
      lines = [] of String
      positional_names = schema.positional
      root = resolve_property(schema.root, schema)

      # Build usage line
      usage_parts = ["Usage: #{command}"]
      positional_names.each do |name|
        prop = root.properties.try(&.[name]?)
        part = (prop.nil? || prop.required?) ? "<#{name}>" : "[#{name}]"
        usage_parts << (name == schema.variadic ? "#{part}..." : part)
      end
      usage_parts << "[options]"
      lines << usage_parts.join(" ")
      lines << ""

      # Arguments section. Whether one is required shows in the usage line.
      unless positional_names.empty?
        lines << "Arguments:"
        entries = [] of {String, String}
        positional_names.each do |name|
          if prop = root.properties.try(&.[name]?)
            entries << {name, help_text_for(resolve_property(prop, schema), required: false)}
          end
        end
        help_columns(lines, entries)
        lines << ""
      end

      # Options section
      lines << "Options:"
      if props = root.properties
        entries = [] of {String, String}
        props.each do |name, prop|
          next if positional_names.includes?(name)
          option_entries(entries, name, prop, "", schema)
        end
        help_columns(lines, entries)
      end

      lines.join("\n")
    end

    # `expanding` holds the `$ref`s being descended through on this path. A ref
    # already in it is recursive (a tree-shaped schema): its option is listed
    # but not expanded again, which would never end.
    private def option_entries(entries : Array({String, String}), name : String, prop : Property, prefix : String, schema : Schema, expanding : Set(String) = Set(String).new)
      ref = prop.ref
      prop = resolve_property(prop, schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"

      entries << {help_flag(full_name, prop), help_text_for(prop, required: true)}
      return if ref && expanding.includes?(ref)

      if prop.type.object? && (nested_props = prop.properties)
        inner = ref ? expanding | Set{ref} : expanding
        nested_props.each do |nested_name, nested_prop|
          option_entries(entries, nested_name, nested_prop, full_name, schema, inner)
        end
      end
    end

    # An option's flag spelling and, unless it's a boolean, its value type.
    private def help_flag(full_name : String, prop : Property) : String
      flag = (short = prop.short) ? "-#{short}, --#{full_name}" : "    --#{full_name}"
      prop.type.boolean? ? flag : "#{flag}=<#{prop.type.to_s.downcase}>"
    end

    # What help says about an argument or option: its description, the
    # separators of a list, the values an enum allows, whether it's required
    # (when `required`), and its default.
    private def help_text_for(prop : Property, required : Bool) : String
      parts = [] of String
      if (desc = prop.description.try(&.rstrip)) && !desc.empty?
        parts << desc
      end
      if separators = prop.separator
        names = separators.map { |separator| "#{separator.to_s.downcase}-" }
        listed = names.size == 1 ? names.first : "#{names[0..-2].join(", ")} or #{names.last}"
        parts << "(#{listed}separated)"
      end
      if (values = prop.enum_values) && !values.empty?
        parts << "[#{values.join("|") { |value| help_value(value) }}]"
      end
      parts << "(required)" if required && prop.required?
      if default = prop.default
        parts << "[default: #{help_value(default)}]"
      end
      parts.join(" ")
    end

    # A string as itself, anything else as JSON (`[1, 2]`, `null`). An empty
    # string is `""`, so that it shows.
    private def help_value(value : JSON::Any) : String
      (string = value.as_s?) && !string.empty? ? string : value.to_json
    end

    # The furthest into a line that the second column of `Arguments:` and
    # `Options:` starts.
    private HELP_COLUMN_LIMIT = 32

    # Lay out `{name, text}` entries in two columns: each text starts two
    # spaces past the widest name, or at `HELP_COLUMN_LIMIT` if that is
    # nearer.
    private def help_columns(lines : Array(String), entries : Array({String, String}))
      column = Math.min((entries.max_of?(&.[0].size) || 0) + 4, HELP_COLUMN_LIMIT)
      entries.each { |name, text| help_entry(lines, "  #{name}", column, text) }
    end

    # Add one listing: `entry`, then `text` from `column` on, or on the next
    # line if `entry` is too wide to leave two spaces before the column. A
    # text of several lines has each one at the column.
    private def help_entry(lines : Array(String), entry : String, column : Int32, text : String?)
      text = text.try(&.rstrip) || ""
      if text.empty?
        lines << entry
        return
      end

      indent = " " * column
      first, *rest = text.split('\n')
      if entry.size + 2 <= column
        lines << "#{entry.ljust(column)}#{first}".rstrip
      else
        lines << entry
        lines << "#{indent}#{first}".rstrip
      end
      rest.each { |line| lines << "#{indent}#{line}".rstrip }
    end
  end
end
