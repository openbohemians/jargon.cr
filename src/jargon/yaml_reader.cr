require "yaml"

module Jargon
  # :nodoc:
  #
  # Reads YAML as `YAML.parse` does (the YAML 1.1 core schema, with merge
  # keys and aliases), except that a plain scalar that reads as a timestamp
  # stays the string it was written as. Jargon hands YAML on as JSON, which
  # has no time type, and a `format: date` value must stay `2026-10-22`, not
  # become `2026-10-22T00:00:00Z`.
  module YAMLReader
    def self.parse(content : String) : YAML::Any
      Parser.new(content, &.parse)
    end

    def self.parse_all(content : String) : Array(YAML::Any)
      Parser.new(content, &.parse_all)
    end

    class Parser < YAML::Schema::Core::Parser
      def new_scalar : YAML::Any
        text = @pull_parser.value
        value = YAML::Schema::Core.parse_scalar(@pull_parser)
        YAML::Any.new(value.is_a?(Time) ? text : value)
      end
    end
  end
end
