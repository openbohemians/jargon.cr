module Jargon
  # One node of a parsed schema: a single option/field/positional, or the root
  # object. Holds its type, validation constraints, CLI hints (`short`, `env`),
  # nested `properties`/`items`, and any consumer-defined `x-` extensions.
  class Property
    # The JSON Schema primitive types Jargon recognizes.
    enum Type
      String
      Integer
      Number
      Boolean
      Array
      Object
      Null
    end

    # What a `separator` names: the characters at which an array option's
    # value is split into items (`"separator": "comma"` reads `-f 1,3` as
    # `[1, 3]`).
    enum Separator
      Comma
      Colon
      Semicolon
      Whitespace

      def splits_at?(char : Char) : Bool
        case self
        in .comma?      then char == ','
        in .colon?      then char == ':'
        in .semicolon?  then char == ';'
        in .whitespace? then char.whitespace?
        end
      end

      def self.names : Array(String)
        values.map(&.to_s.downcase)
      end
    end

    getter name : String
    getter type : Type
    getter description : String?
    getter? required : Bool
    getter default : JSON::Any?
    getter enum_values : Array(JSON::Any)?
    getter properties : Hash(String, Property)?
    getter items : Property?
    getter ref : String?
    getter short : String?
    getter env : String?
    getter separator : Array(Separator)?
    getter minimum : Float64?
    getter maximum : Float64?
    getter exclusive_minimum : Float64?
    getter exclusive_maximum : Float64?
    getter multiple_of : Float64?
    getter min_length : Int32?
    getter max_length : Int32?
    getter min_items : Int32?
    getter max_items : Int32?
    getter? unique_items : Bool
    getter pattern : Regex?
    getter const : JSON::Any?
    getter format : String?
    getter additional_properties : Bool?
    getter? service : Bool
    getter extensions : Hash(String, JSON::Any)

    def initialize(
      @name : String,
      @type : Type,
      @description : String? = nil,
      @required : Bool = false,
      @default : JSON::Any? = nil,
      @enum_values : Array(JSON::Any)? = nil,
      @properties : Hash(String, Property)? = nil,
      @items : Property? = nil,
      @ref : String? = nil,
      @short : String? = nil,
      @env : String? = nil,
      @separator : Array(Separator)? = nil,
      @minimum : Float64? = nil,
      @maximum : Float64? = nil,
      @exclusive_minimum : Float64? = nil,
      @exclusive_maximum : Float64? = nil,
      @multiple_of : Float64? = nil,
      @min_length : Int32? = nil,
      @max_length : Int32? = nil,
      @min_items : Int32? = nil,
      @max_items : Int32? = nil,
      @unique_items : Bool = false,
      @pattern : Regex? = nil,
      @const : JSON::Any? = nil,
      @format : String? = nil,
      @additional_properties : Bool? = nil,
      @service : Bool = false,
      @extensions : Hash(String, JSON::Any) = {} of String => JSON::Any,
    )
    end

    # Build a Property from a JSON Schema node. `name` is the field's key (or
    # "root"); `required_fields` is the enclosing object's `required` list, used
    # to set this field's `required?`.
    def self.from_json(name : String, json : JSON::Any, required_fields : Array(String) = [] of String) : Property
      type = resolve_type(name, json)

      Property.new(
        name: name,
        type: type,
        description: json["description"]?.try(&.as_s?),
        required: required_fields.includes?(name),
        default: json["default"]?,
        enum_values: json["enum"]?.try(&.as_a?),
        properties: parse_properties(type, json),
        items: parse_items(type, json),
        ref: json["$ref"]?.try(&.as_s?),
        short: json["short"]?.try(&.as_s?),
        env: json["env"]?.try(&.as_s?),
        separator: parse_separator(name, type, json),
        minimum: parse_number(json, "minimum"),
        maximum: parse_number(json, "maximum"),
        exclusive_minimum: parse_number(json, "exclusiveMinimum"),
        exclusive_maximum: parse_number(json, "exclusiveMaximum"),
        multiple_of: parse_number(json, "multipleOf"),
        min_length: parse_int(json, "minLength"),
        max_length: parse_int(json, "maxLength"),
        min_items: parse_int(json, "minItems"),
        max_items: parse_int(json, "maxItems"),
        unique_items: json["uniqueItems"]?.try(&.as_bool?) || false,
        pattern: parse_pattern(json),
        const: json["const"]?,
        format: json["format"]?.try(&.as_s?),
        additional_properties: json["additionalProperties"]?.try(&.as_bool?),
        service: json["service"]?.try(&.as_bool?) || false,
        extensions: parse_extensions(json)
      )
    end

    # When type is omitted, infer it from structural keywords (JSON Schema
    # semantics: properties/items imply the shape; omitted type is not "string")
    private def self.resolve_type(name : String, json : JSON::Any) : Type
      declared = json["type"]?.try(&.as_s?)
      type = parse_type(declared || (json["properties"]? ? "object" : (json["items"]? ? "array" : "string")))

      if declared && !type.object? && json["properties"]?
        raise ArgumentError.new("Schema '#{name}' declares type '#{declared}' but has 'properties' (did you mean type: object?)")
      end
      if declared && !type.array? && json["items"]?
        raise ArgumentError.new("Schema '#{name}' declares type '#{declared}' but has 'items' (did you mean type: array?)")
      end

      type
    end

    # `separator`: one name or a list of them, on an array.
    private def self.parse_separator(name : String, type : Type, json : JSON::Any) : Array(Separator)?
      return unless value = json["separator"]?
      if json["$ref"]?
        raise ArgumentError.new("Schema '#{name}' has 'separator' beside '$ref' (put it in the referenced schema)")
      end
      unless type.array?
        raise ArgumentError.new("Schema '#{name}' has 'separator' but isn't an array (did you mean type: array?)")
      end

      entries = value.as_a? || [value]
      separators = entries.map do |entry|
        word = entry.as_s? || entry.to_json
        Separator.values.find { |separator| separator.to_s.downcase == word } ||
          raise ArgumentError.new("Schema '#{name}' has unknown separator '#{word}' (use #{Separator.names.join(", ")})")
      end
      separators.uniq unless separators.empty?
    end

    # Split an array option's value at its separators, trimming each piece and
    # dropping empty ones, so `"a, b,,c"` is `["a", "b", "c"]`.
    def self.split(value : String, separators : Array(Separator)) : Array(String)
      pieces = [] of String
      start = 0
      value.each_char_with_index do |char, i|
        next unless separators.any?(&.splits_at?(char))
        pieces << value[start...i]
        start = i + 1
      end
      pieces << value[start..]
      pieces.map(&.strip).reject(&.empty?)
    end

    private def self.parse_properties(type : Type, json : JSON::Any) : Hash(String, Property)?
      return unless type.object? && (props = json["properties"]?)

      nested_required = json["required"]?.try(&.as_a.map(&.as_s)) || [] of String
      props.as_h.map do |prop_name, prop_schema|
        {prop_name, Property.from_json(prop_name, prop_schema, nested_required)}
      end.to_h
    end

    private def self.parse_items(type : Type, json : JSON::Any) : Property?
      return unless type.array? && (item_schema = json["items"]?)

      Property.from_json("items", item_schema)
    end

    private def self.parse_number(json : JSON::Any, key : String) : Float64?
      json[key]?.try(&.as_f?) || json[key]?.try(&.as_i64?.try(&.to_f))
    end

    private def self.parse_int(json : JSON::Any, key : String) : Int32?
      json[key]?.try(&.as_i?.try(&.to_i32))
    end

    # In JSON Schema (ECMA-262) `$` is the end of the value, where PCRE's
    # would also match before a final newline.
    private def self.parse_pattern(json : JSON::Any) : Regex?
      if pattern_str = json["pattern"]?.try(&.as_s?)
        Regex.new(pattern_str, :dollar_endonly)
      end
    end

    # Consumer-defined extension annotations (x-ui, x-anything): preserved
    # verbatim for introspection, ignored by parsing and validation
    private def self.parse_extensions(json : JSON::Any) : Hash(String, JSON::Any)
      extensions = {} of String => JSON::Any
      if hash = json.as_h?
        hash.each do |key, value|
          extensions[key] = value if key.starts_with?("x-")
        end
      end
      extensions
    end

    private def self.parse_type(type_str : String) : Type
      case type_str.downcase
      when "string"  then Type::String
      when "integer" then Type::Integer
      when "number"  then Type::Number
      when "boolean" then Type::Boolean
      when "array"   then Type::Array
      when "object"  then Type::Object
      when "null"    then Type::Null
      else                Type::String
      end
    end
  end
end
