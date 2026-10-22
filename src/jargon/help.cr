module Jargon
  class CLI
    # Render the program's help text: a command listing when subcommands are
    # defined, an option listing for a flat CLI, or a bare usage line otherwise.
    def help : String
      help_as(program_name)
    end

    # Render help for a single subcommand. `subcommand` is space-separated for
    # nested commands (e.g. `"remote add"`).
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
        "Unknown subcommand: #{subcmd_name}"
      end
    end

    private def help_with_subcommands(command : String) : String
      lines = ["Usage: #{command} <command> [options]", "", "Commands:"]

      width = @subcommands.keys.max_of?(&.size) || 0
      @subcommands.each do |name, subcmd|
        case subcmd
        when Schema
          lines << command_line(name, subcmd.root.description, 2, width)
        when CLI
          # A nested CLI is a group with no description of its own; list its
          # children indented, each aligned within their own column.
          lines << command_line(name, nil, 2, width)
          sub_width = subcmd.subcommands.keys.max_of?(&.size) || 0
          subcmd.subcommands.each do |sub_name, sub|
            description = sub.is_a?(Schema) ? sub.root.description : nil
            lines << command_line(sub_name, description, 4, sub_width)
          end
        end
      end

      lines << ""
      lines << "Run '#{command} <command> --help' for command-specific options."
      lines.join("\n")
    end

    # Format one command listing: the name padded to `width`, followed by its
    # description when present. Trailing padding is trimmed when there is none.
    private def command_line(name : String, description : String?, indent : Int32, width : Int32) : String
      entry = "#{" " * indent}#{name.ljust(width)}"
      (desc = description) ? "#{entry}  #{desc}" : entry.rstrip
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
        if prop = root.properties.try(&.[name]?)
          usage_parts << (prop.required? ? "<#{name}>" : "[#{name}]")
        else
          usage_parts << "<#{name}>"
        end
      end
      usage_parts << "[options]"
      lines << usage_parts.join(" ")
      lines << ""

      # Arguments section
      unless positional_names.empty?
        lines << "Arguments:"
        positional_names.each do |name|
          if prop = root.properties.try(&.[name]?)
            desc = prop.description || ""
            lines << "  #{name}    #{desc}"
          end
        end
        lines << ""
      end

      # Options section
      lines << "Options:"
      if props = root.properties
        props.each do |name, prop|
          next if positional_names.includes?(name)
          build_help_lines(lines, name, prop, "", schema)
        end
      end

      lines.join("\n")
    end

    # `expanding` holds the `$ref`s being descended through on this path. A ref
    # already in it is recursive (a tree-shaped schema): its option is listed
    # but not expanded again, which would never end.
    private def build_help_lines(lines : Array(String), name : String, prop : Property, prefix : String, schema : Schema, expanding : Set(String) = Set(String).new)
      ref = prop.ref
      prop = resolve_property(prop, schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      desc = prop.description || ""

      lines << help_option_line(full_name, prop)
      lines << "      #{desc}" unless desc.empty?
      return if ref && expanding.includes?(ref)

      if prop.type.object? && (nested_props = prop.properties)
        inner = ref ? expanding | Set{ref} : expanding
        nested_props.each do |nested_name, nested_prop|
          build_help_lines(lines, nested_name, nested_prop, full_name, schema, inner)
        end
      end
    end

    # One option's listing: its flag spelling, value type, and required/default.
    private def help_option_line(full_name : String, prop : Property) : String
      type_str = prop.type.to_s.downcase
      required_str = prop.required? ? " (required)" : ""
      # A string as itself, anything else as JSON (`[1, 2]`, `null`).
      default_str = (default = prop.default) ? " [default: #{default.as_s? || default.to_json}]" : ""

      flag_str = if short = prop.short
                   "-#{short}, --#{full_name}"
                 else
                   "    --#{full_name}"
                 end

      if prop.type.boolean?
        "  #{flag_str}#{required_str}#{default_str}"
      else
        "  #{flag_str}=<#{type_str}>#{required_str}#{default_str}"
      end
    end
  end
end
