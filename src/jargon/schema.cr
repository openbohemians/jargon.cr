require "json"
require "./schema/property"

module Jargon
  # A parsed JSON Schema describing one command: its `root` property (the
  # object whose properties are the command's options), the named `positional`
  # arguments, and any reusable `definitions` (`$defs`/`definitions`) that
  # `$ref` resolves against.
  class Schema
    getter root : Property
    getter definitions : Hash(String, Property)
    # The positional arguments' names, in order, without the `*` that marks
    # the variadic one.
    getter positional : Array(String)
    # The positional that takes a list of words, marked in `positional` with a
    # trailing `*` (`["sources*", "dest"]`), or nil when there is none.
    getter variadic : String?

    def initialize(@root : Property, @definitions : Hash(String, Property) = {} of String => Property, @positional : Array(String) = [] of String, @variadic : String? = nil)
      check_variadic
    end

    # Build a Schema from a JSON Schema document (string).
    def self.from_json(json_string : String) : Schema
      json = JSON.parse(json_string)
      from_json_any(json)
    end

    # Build a Schema from a JSON Schema file.
    def self.from_file(path : String) : Schema
      json_string = File.read(path)
      from_json(json_string)
    end

    # Build a Schema from an already-parsed JSON document. The whole document
    # is the root property; `positional` and `definitions`/`$defs` are lifted
    # out alongside it.
    def self.from_json_any(json : JSON::Any) : Schema
      required_fields = json["required"]?.try(&.as_a.map(&.as_s)) || [] of String
      positional = json["positional"]?.try(&.as_a.map(&.as_s)) || [] of String
      starred = positional.select(&.ends_with?("*"))
      if starred.size > 1
        raise ArgumentError.new("Positionals '#{starred[0]}' and '#{starred[1]}' are both variadic (only one can take a list)")
      end

      root = Property.from_json("root", json, required_fields)

      definitions = if defs = json["definitions"]? || json["$defs"]?
                      defs.as_h.map do |def_name, def_schema|
                        {def_name, Property.from_json(def_name, def_schema)}
                      end.to_h
                    else
                      {} of String => Property
                    end

      Schema.new(root, definitions, positional.map(&.rchop("*")), starred.first?.try(&.rchop("*")))
    end

    # Resolve a local `$ref` pointer (e.g. `#/$defs/Name`) to its definition,
    # or nil if the pointer is non-local or unknown.
    def resolve_ref(ref : String) : Property?
      return unless ref.starts_with?("#/")

      parts = ref[2..].split("/")
      return unless parts.size >= 2

      case parts[0]
      when "definitions", "$defs"
        definitions[parts[1]]?
      end
    end

    # Look up a property by dotted path (e.g. "server.port"), descending through
    # object properties and resolving `$ref`s. Returns nil if any segment is
    # missing or a non-final segment isn't an object.
    protected def find_property(key : String) : Property?
      parts = key.split(".")
      current = resolve_property(root)

      parts.each_with_index do |part, i|
        prop = current.properties.try(&.[part]?) || return
        resolved = resolve_property(prop)
        return resolved if i == parts.size - 1
        return unless resolved.type.object?
        current = resolved
      end

      nil
    end

    protected def resolve_property(prop : Property) : Property
      if ref = prop.ref
        resolve_ref(ref) || prop
      else
        prop
      end
    end

    private def check_variadic : Nil
      return unless name = variadic
      prop = find_property(name)
      raise ArgumentError.new("Positional '#{name}*' names no property") unless prop
      raise ArgumentError.new("Positional '#{name}*' isn't an array (did you mean type: array?)") unless prop.type.array?
    end
  end
end
