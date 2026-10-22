require "json"
require "./schema"

module Jargon
  # Schema validation, usable standalone (without the CLI parser) to check a
  # data hash against a `Schema`. This is the same engine `parse`/`run` apply
  # to parsed arguments.
  module Validator
    # Validate data against a schema. Returns an array of error strings (empty if valid).
    def self.validate(data : Hash(String, JSON::Any), schema : Schema) : Array(String)
      errors = [] of String
      root = resolve_property(schema.root, schema)
      return errors unless props = root.properties

      # additionalProperties check at root level
      check_additional_properties(data, root, errors, "", props)

      props.each do |name, prop|
        validate_property(data, name, resolve_property(prop, schema), errors, "", schema)
      end

      errors
    end

    private def self.validate_property(data : Hash(String, JSON::Any), name : String, prop : Property, errors : Array(String), prefix : String, schema : Schema)
      full_name = prefix.empty? ? name : "#{prefix}.#{name}"
      value = data[name]?

      if prop.required? && value.nil?
        errors << "Missing required field: #{full_name}"
        return
      end

      return unless value

      validate_type_match(value, prop, errors, full_name)
      validate_const(value, prop, errors, full_name)
      validate_enum(value, prop, errors, full_name)
      validate_numeric(value, prop, errors, full_name)
      validate_string(value, prop, errors, full_name)
      validate_array(value, prop, errors, full_name, schema)
      validate_object(value, prop, errors, full_name, schema)
    end

    private def self.validate_array_item(value : JSON::Any, prop : Property, errors : Array(String), item_name : String)
      validate_type_match(value, prop, errors, item_name)
      validate_enum(value, prop, errors, item_name)
      validate_numeric(value, prop, errors, item_name)
      validate_string(value, prop, errors, item_name)
    end

    private def self.validate_type_match(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      unless valid_type?(value, prop.type)
        errors << "Invalid type for #{label}: expected #{prop.type}, got #{value.raw.class}"
      end
    end

    private def self.validate_const(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless const_val = prop.const
      unless value == const_val
        errors << "Value for #{label} must be #{const_val.as_s? || const_val.to_json}"
      end
    end

    private def self.validate_enum(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless enum_values = prop.enum_values
      unless enum_values.includes?(value)
        formatted = enum_values.map { |v| v.as_s? || v.to_json }.join(", ")
        errors << "Invalid value for #{label}: must be one of #{formatted}"
      end
    end

    private def self.validate_array(value : JSON::Any, prop : Property, errors : Array(String), label : String, schema : Schema)
      return unless prop.type.array?
      return unless arr = value.as_a?

      if min = prop.min_items
        errors << "#{label} must have at least #{min} items" if arr.size < min
      end
      if max = prop.max_items
        errors << "#{label} must have at most #{max} items" if arr.size > max
      end
      validate_unique_items(arr, prop, errors, label)

      if items_prop = prop.items
        arr.each_with_index do |item, i|
          validate_array_item(item, items_prop, errors, "#{label}[#{i}]")
        end
      end
    end

    private def self.validate_unique_items(arr : Array(JSON::Any), prop : Property, errors : Array(String), label : String)
      return unless prop.unique_items?

      seen = Set(String).new
      arr.each do |item|
        key = item.to_json
        if seen.includes?(key)
          errors << "#{label} must have unique items (duplicate: #{item.as_s? || item.to_json})"
          break
        end
        seen << key
      end
    end

    private def self.validate_object(value : JSON::Any, prop : Property, errors : Array(String), label : String, schema : Schema)
      return unless prop.type.object? && (nested_props = prop.properties)
      return unless nested_data = value.as_h?

      check_additional_properties(nested_data, prop, errors, label, nested_props)
      nested_props.each do |nested_name, nested_prop|
        validate_property(nested_data, nested_name, resolve_property(nested_prop, schema), errors, label, schema)
      end
    end

    # Shared numeric-constraint checks. `label` is the field or item path used
    # in error messages.
    private def self.validate_numeric(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless prop.type.integer? || prop.type.number?
      return unless num = value.as_f? || value.as_i64?.try(&.to_f)

      validate_range(num, prop, errors, label)
      validate_multiple_of(num, prop, errors, label)
    end

    private def self.validate_range(num : Float64, prop : Property, errors : Array(String), label : String)
      if min = prop.minimum
        errors << "Value for #{label} must be >= #{format_num(min)}" if num < min
      end
      if max = prop.maximum
        errors << "Value for #{label} must be <= #{format_num(max)}" if num > max
      end
      if min = prop.exclusive_minimum
        errors << "Value for #{label} must be > #{format_num(min)}" if num <= min
      end
      if max = prop.exclusive_maximum
        errors << "Value for #{label} must be < #{format_num(max)}" if num >= max
      end
    end

    private def self.validate_multiple_of(num : Float64, prop : Property, errors : Array(String), label : String)
      return unless mult = prop.multiple_of
      # Compare the quotient to the nearest integer within a few ulps: float
      # modulo misreports decimal multiples (0.3 % 0.1 == 0.09999999999999998).
      quotient = num / mult
      unless (quotient - quotient.round).abs <= 4 * Float64::EPSILON * Math.max(1.0, quotient.abs)
        errors << "Value for #{label} must be a multiple of #{format_num(mult)}"
      end
    end

    # Shared string-constraint checks (minLength/maxLength/pattern/format).
    # `label` is the field or item path used in error messages.
    private def self.validate_string(value : JSON::Any, prop : Property, errors : Array(String), label : String)
      return unless prop.type.string?
      return unless str = value.as_s?

      if min = prop.min_length
        errors << "Value for #{label} must be at least #{min} characters" if str.size < min
      end
      if max = prop.max_length
        errors << "Value for #{label} must be at most #{max} characters" if str.size > max
      end
      validate_pattern(str, prop, errors, label)
      if fmt = prop.format
        unless valid_format?(str, fmt)
          errors << "Value for #{label} must be a valid #{fmt}"
        end
      end
    end

    # PCRE2 raises, rather than failing to match, on input that isn't valid
    # UTF-8 and when a pattern backtracks past its match limit. Report both as
    # validation errors so hostile input can't crash a parse.
    private def self.validate_pattern(str : String, prop : Property, errors : Array(String), label : String)
      return unless pattern = prop.pattern

      if !str.valid_encoding?
        errors << "Value for #{label} must be valid UTF-8 to match pattern: #{pattern.source}"
      elsif !pattern.matches?(str)
        errors << "Value for #{label} must match pattern: #{pattern.source}"
      end
    rescue ex : Regex::Error
      errors << "Value for #{label} could not be checked against pattern: #{ex.message}"
    end

    private def self.check_additional_properties(data : Hash(String, JSON::Any), prop : Property, errors : Array(String), prefix : String, known_props : Hash(String, Property))
      return unless prop.additional_properties == false

      known_keys = known_props.keys.to_set
      data.each_key do |key|
        unless known_keys.includes?(key)
          full_name = prefix.empty? ? key : "#{prefix}.#{key}"
          errors << "Unknown property '#{full_name}': additionalProperties is false"
        end
      end
    end

    # A whole number prints without a fraction; Int64 holds any below 9e15.
    private def self.format_num(n : Float64) : String
      n == n.trunc && n.abs < 9.0e15 ? n.to_i64.to_s : n.to_s
    end

    private def self.valid_format?(value : String, format : String) : Bool
      case format
      when "email"
        valid_format_email?(value)
      when "uri", "url"
        valid_format_uri?(value)
      when "uuid"
        valid_format_uuid?(value)
      when "date"
        valid_format_date?(value)
      when "time"
        valid_format_time?(value)
      when "date-time"
        valid_format_date_time?(value)
      when "ipv4"
        valid_format_ipv4?(value)
      when "ipv6"
        valid_format_ipv6?(value)
      when "hostname"
        valid_format_hostname?(value)
      when "path"
        true # Any string is a valid path; expansion happens at the CLI layer
      else
        true # Unknown formats pass (per JSON Schema spec)
      end
    end

    # Dot-free domain labels keep this linear (a looser `[^@\s]+\.[^@\s]+`
    # backtracks quadratically); the RFC 5321 length cap bounds the
    # per-label stack the repeated group uses.
    private def self.valid_format_email?(value : String) : Bool
      value.bytesize <= 254 && format_match?(value, /\A[^@\s]+@[^@\s.]+(\.[^@\s.]+)+\z/)
    end

    private def self.valid_format_uri?(value : String) : Bool
      format_match?(value, /\A[a-z][a-z0-9+.-]*:\/\/.+\z/i)
    end

    private def self.valid_format_uuid?(value : String) : Bool
      format_match?(value, /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    private def self.valid_format_date?(value : String) : Bool
      format_match?(value, /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
    end

    private def self.valid_format_time?(value : String) : Bool
      format_match?(value, /\A[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})?\z/)
    end

    private def self.valid_format_date_time?(value : String) : Bool
      format_match?(value, /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})?\z/)
    end

    private def self.valid_format_ipv4?(value : String) : Bool
      parts = value.split(".")
      parts.size == 4 && parts.all? { |part| part.matches?(/\A[0-9]{1,3}\z/) && part.to_i <= 255 }
    end

    private def self.valid_format_ipv6?(value : String) : Bool
      format_match?(value, /\A([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}\z/i)
    end

    # RFC 1035 caps a name at 253 bytes, which also bounds the stack the
    # repeated label group uses.
    private def self.valid_format_hostname?(value : String) : Bool
      value.bytesize <= 253 && format_match?(value, /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\z/i)
    end

    # Bytes that aren't valid UTF-8 can't spell any textual format, and PCRE2
    # would raise on them rather than fail to match. Should a value still
    # exhaust a regex limit, it is simply not that format.
    private def self.format_match?(value : String, regex : Regex) : Bool
      value.valid_encoding? && value.matches?(regex)
    rescue Regex::Error
      false
    end

    private def self.valid_type?(value : JSON::Any, expected : Property::Type) : Bool
      case expected
      when Property::Type::String  then value.as_s? != nil
      when Property::Type::Integer then value.as_i64? != nil
      when Property::Type::Number  then value.as_f? != nil || value.as_i64? != nil
      when Property::Type::Boolean then value.as_bool? != nil
      when Property::Type::Array   then value.as_a? != nil
      when Property::Type::Object  then value.as_h? != nil
      when Property::Type::Null    then value.raw.nil?
      else                              true
      end
    end

    private def self.resolve_property(prop : Property, schema : Schema) : Property
      if ref = prop.ref
        schema.resolve_ref(ref) || prop
      else
        prop
      end
    end
  end
end
