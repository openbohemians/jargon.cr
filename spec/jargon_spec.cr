require "./spec_helper"

describe Jargon do
  describe "API" do
    it "Jargon::CLI.from_json creates CLI from JSON schema" do
      cli = Jargon::CLI.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }), "myapp")

      cli.should be_a(Jargon::CLI)
      cli.program_name.should eq("myapp")
      result = cli.parse(["--name", "test"])
      result["name"].as_s.should eq("test")
    end

    it "Jargon.cli with json: creates CLI from JSON string" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      cli.should be_a(Jargon::CLI)
      cli.program_name.should eq("myapp")
      result = cli.parse(["--verbose"])
      result["verbose"].as_bool.should be_true
    end

    it "Jargon.cli with file: creates CLI from file" do
      # Use existing schema file if available, or create temp one
      File.write("/tmp/test_schema.json", %({"type": "object", "properties": {"name": {"type": "string"}}}))
      begin
        cli = Jargon.cli("myapp", file: "/tmp/test_schema.json")
        cli.should be_a(Jargon::CLI)
        cli.program_name.should eq("myapp")
        result = cli.parse(["--name", "test"])
        result["name"].as_s.should eq("test")
      ensure
        File.delete("/tmp/test_schema.json")
      end
    end

    it "Jargon.from_json remains for backwards compatibility" do
      cli = Jargon.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }), "myapp")

      cli.should be_a(Jargon::CLI)
      result = cli.parse(["--name", "test"])
      result["name"].as_s.should eq("test")
    end
  end

  describe "basic parsing" do
    it "parses string values with equals style" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name=John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end

    it "does not treat a colon as an assignment separator" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name:John"])
      result.valid?.should be_false
      result.data.as_h.has_key?("name").should be_false
      result.errors.should eq(["Unexpected argument 'name:John'"])
    end

    it "passes JSON-like operands through literally" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["doc"],
        "properties": {
          "doc": {"type": "string"},
          "name": {"type": "string"}
        }
      }))

      result = cli.parse([%({"name":"John"}), "--name", "Jane"])
      result.valid?.should be_true
      result["doc"].as_s.should eq(%({"name":"John"}))
      result["name"].as_s.should eq("Jane")
    end

    it "parses string values with traditional style" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--name", "John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end

    it "parses --key=value style" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--name=John"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
    end
  end

  describe "type coercion" do
    it "coerces integer values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["count=42"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(42)
    end

    it "coerces number values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["rate=3.14"])
      result.valid?.should be_true
      result["rate"].as_f.should eq(3.14)
    end

    it "coerces boolean values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["verbose=true"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true

      result = cli.parse(["verbose=false"])
      result["verbose"].as_bool.should be_false
    end

    it "handles boolean flags without value" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--verbose"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
    end

    it "handles boolean flags with explicit true/false value" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "enabled": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--enabled", "false"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_false

      result = cli.parse(["--enabled", "true"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_true

      result = cli.parse(["--enabled", "no"])
      result.valid?.should be_true
      result["enabled"].as_bool.should be_false
    end

    it "does not consume non-boolean value after boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "verbose": {"type": "boolean"},
          "file": {"type": "string"}
        }
      }))

      result = cli.parse(["--verbose", "output.txt"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
      result["file"].as_s.should eq("output.txt")
    end

    it "accepts various boolean value formats" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "flag": {"type": "boolean"}
        }
      }))

      %w[true yes on 1 TRUE Yes ON].each do |val|
        result = cli.parse(["flag=#{val}"])
        result.valid?.should be_true
        result["flag"].as_bool.should be_true
      end

      %w[false no off 0 FALSE No OFF].each do |val|
        result = cli.parse(["flag=#{val}"])
        result.valid?.should be_true
        result["flag"].as_bool.should be_false
      end
    end

    it "errors on invalid boolean values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["verbose=treu"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid boolean value 'treu'")
      result.errors.first.should contain("true/false")
    end

    it "coerces array values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "tags": {"type": "array", "items": {"type": "string"}}
        }
      }))

      result = cli.parse(["tags=a,b,c"])
      result.valid?.should be_true
      result["tags"].as_a.map(&.as_s).should eq(["a", "b", "c"])
    end

    it "coerces comma-separated array items to the items type" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "nums": {"type": "array", "items": {"type": "integer"}}
        }
      }))

      result = cli.parse(["--nums", "1, 2,3"])
      result.valid?.should be_true
      result["nums"].as_a.map(&.as_i64).should eq([1, 2, 3])

      result = cli.parse(["--nums", "1,x"])
      result.valid?.should be_false
      result.errors.first.should eq("Invalid integer value 'x' for nums")
    end
  end

  describe "nested objects" do
    it "parses nested properties with dot notation" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "age": {"type": "integer"}
            }
          }
        }
      }))

      result = cli.parse(["user.name=John", "user.age=30"])
      result.valid?.should be_true
      result["user"]["name"].as_s.should eq("John")
      result["user"]["age"].as_i64.should eq(30)
    end

    it "handles deeply nested properties" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "config": {
            "type": "object",
            "properties": {
              "database": {
                "type": "object",
                "properties": {
                  "host": {"type": "string"}
                }
              }
            }
          }
        }
      }))

      result = cli.parse(["config.database.host=localhost"])
      result.valid?.should be_true
      result["config"]["database"]["host"].as_s.should eq("localhost")
    end
  end

  describe "validation" do
    it "validates required fields" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("Missing required field: name")
    end

    it "validates enum values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "color": {"type": "string", "enum": ["red", "green", "blue"]}
        }
      }))

      result = cli.parse(["color=red"])
      result.valid?.should be_true

      result = cli.parse(["color=yellow"])
      result.valid?.should be_false
    end

    it "validates types" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["count=42"])
      result.valid?.should be_true
    end

    it "validates array item enums" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "tags": {
            "type": "array",
            "items": {"type": "string", "enum": ["alpha", "beta", "stable"]}
          }
        }
      }))

      result = cli.parse(["--tags", "alpha,beta"])
      result.valid?.should be_true

      result = cli.parse(["--tags", "alpha,invalid,beta"])
      result.valid?.should be_false
      result.errors.first.should contain("tags[1]")
      result.errors.first.should contain("must be one of")
    end

    it "validates minimum and maximum for integers" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "port": {"type": "integer", "minimum": 1, "maximum": 65535}
        }
      }))

      result = cli.parse(["--port", "8080"])
      result.valid?.should be_true

      result = cli.parse(["--port", "0"])
      result.valid?.should be_false
      result.errors.first.should contain(">= 1")

      result = cli.parse(["--port", "70000"])
      result.valid?.should be_false
      result.errors.first.should contain("<= 65535")
    end

    it "validates minimum and maximum for numbers" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "ratio": {"type": "number", "minimum": 0.0, "maximum": 1.0}
        }
      }))

      result = cli.parse(["--ratio", "0.5"])
      result.valid?.should be_true

      result = cli.parse(["--ratio", "-0.1"])
      result.valid?.should be_false

      result = cli.parse(["--ratio", "1.5"])
      result.valid?.should be_false
    end

    it "validates string patterns" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "code": {"type": "string", "pattern": "^[A-Z]{2}[0-9]{3}$"}
        }
      }))

      result = cli.parse(["--code", "AB123"])
      result.valid?.should be_true

      result = cli.parse(["--code", "invalid"])
      result.valid?.should be_false
      result.errors.first.should contain("must match pattern")
    end

    it "formats enum error messages nicely" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "level": {"type": "string", "enum": ["debug", "info", "warn"]}
        }
      }))

      result = cli.parse(["--level", "bad"])
      result.valid?.should be_false
      result.errors.first.should eq("Invalid value for level: must be one of debug, info, warn")
    end

    it "validates exclusiveMinimum and exclusiveMaximum" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "value": {"type": "number", "exclusiveMinimum": 0, "exclusiveMaximum": 100}
        }
      }))

      result = cli.parse(["--value", "50"])
      result.valid?.should be_true

      result = cli.parse(["--value", "0"])
      result.valid?.should be_false
      result.errors.first.should contain("> 0")

      result = cli.parse(["--value", "100"])
      result.valid?.should be_false
      result.errors.first.should contain("< 100")
    end

    it "validates minLength and maxLength" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "password": {"type": "string", "minLength": 8, "maxLength": 20}
        }
      }))

      result = cli.parse(["--password", "goodpass123"])
      result.valid?.should be_true

      result = cli.parse(["--password", "short"])
      result.valid?.should be_false
      result.errors.first.should contain("at least 8 characters")

      result = cli.parse(["--password", "thispasswordiswaytoolongtobevalid"])
      result.valid?.should be_false
      result.errors.first.should contain("at most 20 characters")
    end

    it "validates minItems and maxItems" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "files": {"type": "array", "minItems": 1, "maxItems": 3}
        }
      }))

      result = cli.parse(["--files", "a,b"])
      result.valid?.should be_true

      result = cli.parse(["--files", "a,b,c,d"])
      result.valid?.should be_false
      result.errors.first.should contain("at most 3 items")
    end

    it "validates const values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "version": {"type": "string", "const": "v1"}
        }
      }))

      result = cli.parse(["--version", "v1"])
      result.valid?.should be_true

      result = cli.parse(["--version", "v2"])
      result.valid?.should be_false
      result.errors.first.should contain("must be v1")
    end

    it "validates uniqueItems" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "tags": {"type": "array", "uniqueItems": true}
        }
      }))

      result = cli.parse(["--tags", "a,b,c"])
      result.valid?.should be_true

      result = cli.parse(["--tags", "a,b,a"])
      result.valid?.should be_false
      result.errors.first.should contain("unique items")
      result.errors.first.should contain("duplicate: a")
    end

    it "validates multipleOf" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "multipleOf": 5}
        }
      }))

      result = cli.parse(["--count", "10"])
      result.valid?.should be_true

      result = cli.parse(["--count", "7"])
      result.valid?.should be_false
      result.errors.first.should contain("multiple of 5")
    end

    it "validates decimal multipleOf without float modulo error" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "step": {"type": "number", "multipleOf": 0.1},
          "price": {"type": "number", "multipleOf": 0.01}
        }
      }))

      cli.parse(["--step", "0.3"]).valid?.should be_true
      cli.parse(["--price", "19.99"]).valid?.should be_true

      result = cli.parse(["--step", "0.35"])
      result.valid?.should be_false
      result.errors.first.should contain("multiple of 0.1")
    end

    it "validates format: email" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "email": {"type": "string", "format": "email"}
        }
      }))

      result = cli.parse(["--email", "test@example.com"])
      result.valid?.should be_true

      result = cli.parse(["--email", "not-an-email"])
      result.valid?.should be_false
      result.errors.first.should contain("valid email")
    end

    it "rejects pathological email and hostname values without exhausting the regex engine" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "email": {"type": "string", "format": "email"},
          "host": {"type": "string", "format": "hostname"}
        }
      }))

      cli.parse(["--email", "a@" + "." * 50_000 + "@"]).errors.should eq(["Value for email must be a valid email"])
      cli.parse(["--email", "x@" + "a." * 50_000 + "a"]).errors.should eq(["Value for email must be a valid email"])
      cli.parse(["--host", "a." * 50_000 + "a"]).errors.should eq(["Value for host must be a valid hostname"])
      cli.parse(["--email", "first.last@mail.example.co.uk", "--host", "mail.example.co.uk"]).valid?.should be_true
    end

    it "reports invalid UTF-8 as a validation error rather than raising" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "code": {"type": "string", "pattern": "^a"},
          "email": {"type": "string", "format": "email"}
        }
      }))
      bad = String.new(Bytes[0x61, 0xFF, 0x62])

      cli.parse(["--code", bad]).errors.should eq(["Value for code must be valid UTF-8 to match pattern: ^a"])
      cli.parse(["--email", bad]).errors.should eq(["Value for email must be a valid email"])
    end

    it "reports a pattern that exhausts the regex match limit rather than raising" do
      cli = Jargon.cli("cli", json: %q({
        "type": "object",
        "properties": {
          "word": {"type": "string", "pattern": "^(a+)+$"}
        }
      }))

      result = cli.parse(["--word", "a" * 30 + "b"])
      result.valid?.should be_false
      result.errors.first.should contain("could not be checked against pattern")
    end

    it "validates format: uri" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "url": {"type": "string", "format": "uri"}
        }
      }))

      result = cli.parse(["--url", "https://example.com/path"])
      result.valid?.should be_true

      result = cli.parse(["--url", "not-a-url"])
      result.valid?.should be_false
    end

    it "validates format: uuid" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "id": {"type": "string", "format": "uuid"}
        }
      }))

      result = cli.parse(["--id", "550e8400-e29b-41d4-a716-446655440000"])
      result.valid?.should be_true

      result = cli.parse(["--id", "not-a-uuid"])
      result.valid?.should be_false
    end

    it "validates format: date" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "date": {"type": "string", "format": "date"}
        }
      }))

      result = cli.parse(["--date", "2024-01-15"])
      result.valid?.should be_true

      result = cli.parse(["--date", "01-15-2024"])
      result.valid?.should be_false
    end

    it "validates format: ipv4" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "ip": {"type": "string", "format": "ipv4"}
        }
      }))

      result = cli.parse(["--ip", "192.168.1.1"])
      result.valid?.should be_true

      result = cli.parse(["--ip", "999.999.999.999"])
      result.valid?.should be_false
    end

    it "validates format: path (always valid)" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string", "format": "path"}
        }
      }))

      result = cli.parse(["--file", "/tmp/test.txt"])
      result.valid?.should be_true

      result = cli.parse(["--file", "relative/path"])
      result.valid?.should be_true
    end

    it "expands ~ in format: path values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string", "format": "path"}
        }
      }))

      result = cli.parse(["--file", "~/documents/test.txt"])
      result.valid?.should be_true
      result["file"].as_s.should eq(Path.home.to_s + "/documents/test.txt")

      result = cli.parse(["--file", "~"])
      result["file"].as_s.should eq(Path.home.to_s)
    end

    it "does not expand ~ in non-path strings" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--name", "~/something"])
      result["name"].as_s.should eq("~/something")
    end
  end

  describe "service hint" do
    it "exposes service? on root property" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "service": true,
        "properties": {
          "port": {"type": "integer"}
        }
      }))

      cli.schema.not_nil!.root.service?.should be_true
    end

    it "defaults service? to false" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      cli.schema.not_nil!.root.service?.should be_false
    end
  end

  describe "defaults" do
    it "applies default values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse([] of String)
      result["name"].as_s.should eq("anonymous")
    end

    it "does not override provided values with defaults" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string", "default": "anonymous"}
        }
      }))

      result = cli.parse(["name=John"])
      result["name"].as_s.should eq("John")
    end
  end

  describe "help" do
    it "generates help text" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string", "description": "The user name"}
        },
        "required": ["name"]
      }))

      help = cli.help
      help.should contain("myapp")
      help.should contain("--name")
      help.should contain("required")
      help.should contain("The user name")
    end
  end

  describe "mixed styles" do
    it "accepts mixed argument styles" do
      cli = Jargon.cli("cat", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"},
          "active": {"type": "boolean"}
        }
      }))

      result = cli.parse(["name=John", "--age", "30", "active=true"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["age"].as_i64.should eq(30)
      result["active"].as_bool.should be_true
    end
  end

  describe "JSON output" do
    it "outputs valid JSON" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["name=John", "count=42"])
      json = result.to_json
      parsed = JSON.parse(json)
      parsed["name"].as_s.should eq("John")
      parsed["count"].as_i64.should eq(42)
    end
  end

  describe "$ref resolution" do
    it "resolves local $ref to $defs" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "billing": {"$ref": "#/$defs/address"},
          "shipping": {"$ref": "#/$defs/address"}
        },
        "$defs": {
          "address": {
            "type": "object",
            "properties": {
              "street": {"type": "string"},
              "city": {"type": "string"}
            }
          }
        }
      }))

      result = cli.parse(["billing.street=123 Main", "billing.city=NYC", "shipping.city=LA"])
      result.valid?.should be_true
      result["billing"]["street"].as_s.should eq("123 Main")
      result["billing"]["city"].as_s.should eq("NYC")
      result["shipping"]["city"].as_s.should eq("LA")
    end

    it "resolves local $ref to definitions" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {"$ref": "#/definitions/person"}
        },
        "definitions": {
          "person": {
            "type": "object",
            "properties": {
              "name": {"type": "string"},
              "age": {"type": "integer"}
            }
          }
        }
      }))

      result = cli.parse(["user.name=John", "user.age=30"])
      result.valid?.should be_true
      result["user"]["name"].as_s.should eq("John")
      result["user"]["age"].as_i64.should eq(30)
    end
  end

  describe "positional arguments" do
    it "parses positional args in order" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name", "count"],
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["John", "42"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["count"].as_i64.should eq(42)
    end

    it "mixes positional and flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name", "count"],
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["John", "--verbose", "42"])
      result.valid?.should be_true
      result["name"].as_s.should eq("John")
      result["count"].as_i64.should eq(42)
      result["verbose"].as_bool.should be_true
    end

    it "errors on unexpected positional args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["John", "extra"])
      result.valid?.should be_false
      result.errors.should contain("Unexpected argument 'extra'")
    end

    it "validates required positional args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("Missing required field: name")
    end
  end

  describe "variadic positionals" do
    it "collects multiple arguments into array positional" do
      cli = Jargon.cli("cli", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array", "description": "Input files"}
        }
      }))

      result = cli.parse(["a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])
    end

    it "handles flags mixed with variadic positionals" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"},
          "number": {"type": "boolean", "short": "n"}
        }
      }))

      result = cli.parse(["-n", "a.txt", "b.txt"])
      result.valid?.should be_true
      result["number"].as_bool.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt"])
    end

    it "handles non-array positional followed by array positional" do
      cli = Jargon.cli("cp", json: %q({
        "type": "object",
        "positional": ["dest", "sources"],
        "properties": {
          "dest": {"type": "string"},
          "sources": {"type": "array"}
        }
      }))

      result = cli.parse(["target/", "a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["dest"].as_s.should eq("target/")
      result["sources"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])
    end

    it "returns empty array when no arguments for variadic" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"}
        }
      }))

      result = cli.parse([] of String)
      result.valid?.should be_true
      result["files"].as_a.should be_empty
    end

    it "stops collecting at flags (flags should come first)" do
      cli = Jargon.cli("cat", json: %q({
        "type": "object",
        "positional": ["files"],
        "properties": {
          "files": {"type": "array"},
          "number": {"type": "boolean", "short": "n"}
        }
      }))

      # Correct usage: flags first
      result = cli.parse(["-n", "a.txt", "b.txt", "c.txt"])
      result.valid?.should be_true
      result["number"].as_bool.should be_true
      result["files"].as_a.map(&.as_s).should eq(["a.txt", "b.txt", "c.txt"])

      # Incorrect usage: flag after positionals stops collection
      result2 = cli.parse(["a.txt", "-n", "b.txt"])
      result2.valid?.should be_false
      result2["files"].as_a.map(&.as_s).should eq(["a.txt"])
      result2["number"].as_bool.should be_true
      result2.errors.should contain("Unexpected argument 'b.txt'")
    end

    it "captures tokens containing ':' or '=' literally (greedy)" do
      cli = Jargon.cli("add", json: %q({
        "type": "object",
        "positional": ["items"],
        "properties": {
          "amount": {"type": "number"},
          "items": {"type": "array"}
        }
      }))

      result = cli.parse(["Expenses:Food", "42", "Expenses:Income:Salary", "k=v"])
      result.valid?.should be_true
      result["items"].as_a.map(&.as_s).should eq(["Expenses:Food", "42", "Expenses:Income:Salary", "k=v"])
    end

    it "still breaks collection at a real flag, not at ':' tokens" do
      cli = Jargon.cli("add", json: %q({
        "type": "object",
        "positional": ["items"],
        "properties": {
          "amount": {"type": "number"},
          "items": {"type": "array"}
        }
      }))

      result = cli.parse(["a:b", "c:d", "--amount", "9"])
      result.valid?.should be_true
      result["items"].as_a.map(&.as_s).should eq(["a:b", "c:d"])
      result["amount"].as_f.should eq(9.0)
    end
  end

  describe "negative number arguments" do
    it "accepts a negative number as a scalar positional" do
      cli = Jargon.cli("spend", json: %q({
        "type": "object",
        "positional": ["amount", "account"],
        "properties": {
          "amount": {"type": "number"},
          "account": {"type": "string"}
        }
      }))

      result = cli.parse(["-50", "Expenses"])
      result.valid?.should be_true
      result["amount"].as_f.should eq(-50.0)
      result["account"].as_s.should eq("Expenses")
    end

    it "accepts a negative number as a flag value" do
      cli = Jargon.cli("spend", json: %q({
        "type": "object",
        "properties": {"amount": {"type": "number"}}
      }))

      result = cli.parse(["--amount", "-3.14"])
      result.valid?.should be_true
      result["amount"].as_f.should eq(-3.14)
    end

    it "collects negative numbers inside an untyped variadic positional" do
      cli = Jargon.cli("nums", json: %q({
        "type": "object",
        "positional": ["vals"],
        "properties": {"vals": {"type": "array"}}
      }))

      result = cli.parse(["-1", "-50", "-3.14"])
      result.valid?.should be_true
      result["vals"].as_a.map(&.as_s).should eq(["-1", "-50", "-3.14"])
    end

    it "coerces variadic items to the array's declared item type" do
      cli = Jargon.cli("nums", json: %q({
        "type": "object",
        "positional": ["vals"],
        "properties": {
          "vals": {"type": "array", "items": {"type": "number"}}
        }
      }))

      result = cli.parse(["1", "-50", "3.14"])
      result.valid?.should be_true
      result["vals"].as_a.map(&.as_f).should eq([1.0, -50.0, 3.14])
    end

    it "reports a per-item error for a non-numeric variadic token" do
      cli = Jargon.cli("nums", json: %q({
        "type": "object",
        "positional": ["vals"],
        "properties": {
          "vals": {"type": "array", "items": {"type": "integer"}}
        }
      }))

      result = cli.parse(["1", "oops", "3"])
      result.valid?.should be_false
      result.errors.should contain("Invalid integer value 'oops' for vals")
    end

    it "still treats -ab (alpha short cluster) as flags, not a value" do
      cli = Jargon.cli("app", json: %q({
        "type": "object",
        "properties": {
          "a": {"type": "boolean", "short": "a"},
          "b": {"type": "boolean", "short": "b"}
        }
      }))

      result = cli.parse(["-ab"])
      result.valid?.should be_true
      result["a"].as_bool.should be_true
      result["b"].as_bool.should be_true
    end
  end

  describe "bare_assignment toggle" do
    bare_schema = %q({
      "type": "object",
      "properties": {
        "host": {"type": "string"},
        "verbose": {"type": "boolean", "short": "v"}
      }
    })

    it "implicitly assigns a bare key=value when on (default)" do
      cli = Jargon.cli("app", json: bare_schema)
      result = cli.parse(["host=8080"])
      result.valid?.should be_true
      result["host"].as_s.should eq("8080")
    end

    it "rejects a bare key=value as an unexpected argument when off" do
      cli = Jargon.cli("app", json: bare_schema)
      cli.bare_assignment(false)
      result = cli.parse(["host=8080"])
      result.valid?.should be_false
      result.data.as_h.has_key?("host").should be_false
      result.errors.should contain("Unexpected argument 'host=8080'")
    end

    it "lets an open positional slot capture an = operand literally even when on" do
      cli = Jargon.cli("spend", json: %q({
        "type": "object",
        "positional": ["amount", "account"],
        "properties": {
          "host": {"type": "string"},
          "amount": {"type": "number"},
          "account": {"type": "string"}
        }
      }))
      # The positional 'account' wins before the implicit-assignment path runs,
      # so 'host' is never assigned regardless of the toggle.
      result = cli.parse(["1", "host=8080"])
      result.valid?.should be_true
      result["amount"].as_f.should eq(1.0)
      result["account"].as_s.should eq("host=8080")
      result.data.as_h.has_key?("host").should be_false
    end

    it "leaves --flag=value working when bare assignment is off" do
      cli = Jargon.cli("app", json: bare_schema)
      cli.bare_assignment(false)
      result = cli.parse(["--host=db"])
      result.valid?.should be_true
      result["host"].as_s.should eq("db")
    end
  end

  describe "end-of-options (--)" do
    it "captures flag-like tokens after -- into a variadic positional" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "positional": ["cmd", "rest"],
        "properties": {
          "verbose": {"type": "boolean", "short": "v"},
          "cmd": {"type": "string"},
          "rest": {"type": "array"}
        }
      }))

      result = cli.parse(["--verbose", "--", "echo", "--foo", "bar"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
      result["cmd"].as_s.should eq("echo")
      result["rest"].as_a.map(&.as_s).should eq(["--foo", "bar"])
    end

    it "treats --help after -- as a literal operand, not a help request" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "positional": ["rest"],
        "properties": {"rest": {"type": "array"}}
      }))

      result = cli.parse(["--", "--help"])
      result.help_requested?.should be_false
      result["rest"].as_a.map(&.as_s).should eq(["--help"])
    end

    it "discards the -- marker and parses options before it normally" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "positional": ["rest"],
        "properties": {"rest": {"type": "array"}}
      }))

      result = cli.parse(["--", "--flag", "-x", "value"])
      result.valid?.should be_true
      result["rest"].as_a.map(&.as_s).should eq(["--flag", "-x", "value"])
    end

    it "treats a second -- as a literal operand" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "positional": ["rest"],
        "properties": {"rest": {"type": "array"}}
      }))

      result = cli.parse(["--", "a", "--", "b"])
      result.valid?.should be_true
      result["rest"].as_a.map(&.as_s).should eq(["a", "--", "b"])
    end

    it "yields an empty tail when nothing follows --" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "positional": ["rest"],
        "properties": {"rest": {"type": "array"}}
      }))

      result = cli.parse(["--"])
      result.valid?.should be_true
      result["rest"].as_a.should be_empty
    end

    it "works within a subcommand's arguments" do
      cli = Jargon.new("app")
      cli.subcommand("run", json: %({
        "type": "object",
        "positional": ["argv"],
        "properties": {"argv": {"type": "array"}}
      }))

      result = cli.parse(["run", "--", "ls", "-la", "--color"])
      result.valid?.should be_true
      result.subcommand.should eq("run")
      result["argv"].as_a.map(&.as_s).should eq(["ls", "-la", "--color"])
    end
  end

  describe "short flags" do
    it "parses short flags" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-n", "5"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(5)
    end

    it "parses short boolean flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-v"])
      result.valid?.should be_true
      result["verbose"].as_bool.should be_true
    end

    it "mixes short and long flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["-n", "5", "--verbose"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(5)
      result["verbose"].as_bool.should be_true
    end

    it "parses combined short boolean flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"},
          "force": {"type": "boolean", "short": "f"}
        }
      }))

      result = cli.parse(["-avf"])
      result.valid?.should be_true
      result["all"].as_bool.should be_true
      result["verbose"].as_bool.should be_true
      result["force"].as_bool.should be_true
    end

    it "parses combined short flags with other args" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"},
          "output": {"type": "string", "short": "o"}
        }
      }))

      result = cli.parse(["-av", "-o", "file.txt"])
      result.valid?.should be_true
      result["all"].as_bool.should be_true
      result["verbose"].as_bool.should be_true
      result["output"].as_s.should eq("file.txt")
    end

    it "errors on combined flags with non-boolean" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-an"])
      result.valid?.should be_false
      result.errors.first.should contain("Cannot combine non-boolean flag '-n'")
    end

    it "errors on combined flags with unknown flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "short": "a"},
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-avx"])
      result.valid?.should be_false
      result.errors.first.should contain("Unknown option '-x' in '-avx'")
    end

    it "errors on unknown short flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-x"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '-x'. Available: -n")
    end

    it "errors on unknown long flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["--unknown", "value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--unknown'. Available: --name, --count")
    end

    it "errors on unknown key=value style option" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["unknown=value"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option 'unknown'. Available: name")
    end
  end

  describe "typo suggestions" do
    it "suggests similar long flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"},
          "version": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--verbos"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--verbos'. Did you mean '--verbose'?")
    end

    it "suggests similar options for key=value style" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "output": {"type": "string"},
          "format": {"type": "string"}
        }
      }))

      result = cli.parse(["outpt=file.txt"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option 'outpt'. Did you mean 'output'?")
    end

    it "does not suggest when distance is too large" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--xyz"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '--xyz'. Available: --verbose")
    end

    it "does not suggest for single-character flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      }))

      result = cli.parse(["-x"])
      result.valid?.should be_false
      result.errors.should contain("Unknown option '-x'. Available: -v")
    end
  end

  describe "subcommands" do
    it "parses subcommand with its options" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["run", "test.cr", "--verbose"])
      result.valid?.should be_true
      result.subcommand.should eq("run")
      result["file"].as_s.should eq("test.cr")
      result["verbose"].as_bool.should be_true
    end

    it "errors on missing subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))

      result = cli.parse([] of String)
      result.valid?.should be_false
      result.errors.should contain("No subcommand specified")
    end

    it "errors on unknown subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["unknown"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: unknown")
    end

    it "parses multiple subcommands independently" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10, "short": "n"}
        }
      }))

      result1 = cli.parse(["index", "--rebuild"])
      result1.valid?.should be_true
      result1.subcommand.should eq("index")
      result1["rebuild"].as_bool.should be_true

      result2 = cli.parse(["query", "retry backoff", "-n", "5"])
      result2.valid?.should be_true
      result2.subcommand.should eq("query")
      result2["query_text"].as_s.should eq("retry backoff")
      result2["top"].as_i64.should eq(5)
    end

    it "applies defaults in subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "top": {"type": "integer", "default": 10}
        }
      }))

      result = cli.parse(["query"])
      result.valid?.should be_true
      result["top"].as_i64.should eq(10)
    end

    it "validates required fields in subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "positional": ["result_id"],
        "properties": {
          "result_id": {"type": "string"}
        },
        "required": ["result_id"]
      }))

      result = cli.parse(["mark"])
      result.valid?.should be_false
      result.errors.should contain("Missing required field: result_id")
    end

    it "uses default subcommand when no subcommand given" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10, "short": "n"}
        }
      }))
      cli.default_subcommand("query")

      result = cli.parse(["retry backoff", "-n", "5"])
      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("retry backoff")
      result["top"].as_i64.should eq(5)
    end

    it "uses default subcommand with empty args" do
      cli = Jargon.new("myapp")
      cli.subcommand("list", json: %({
        "type": "object",
        "properties": {
          "all": {"type": "boolean", "default": false}
        }
      }))
      cli.default_subcommand("list")

      result = cli.parse([] of String)
      result.valid?.should be_true
      result.subcommand.should eq("list")
      result["all"].as_bool.should be_false
    end

    it "prefers explicit subcommand over default" do
      cli = Jargon.new("xerp")
      cli.subcommand("index", json: %({
        "type": "object",
        "properties": {
          "rebuild": {"type": "boolean"}
        }
      }))
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["query_text"],
        "properties": {
          "query_text": {"type": "string"}
        }
      }))
      cli.default_subcommand("query")

      result = cli.parse(["index", "--rebuild"])
      result.valid?.should be_true
      result.subcommand.should eq("index")
      result["rebuild"].as_bool.should be_true
    end

    it "loads subcommand from JSON file" do
      File.write("/tmp/test_subcmd.json", %({
        "type": "object",
        "properties": {
          "url": {"type": "string"}
        }
      }))
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", file: "/tmp/test_subcmd.json")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_subcmd.json")
      end
    end

    it "loads subcommand from YAML file" do
      File.write("/tmp/test_subcmd.yaml", <<-YAML)
        type: object
        properties:
          url:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("fetch", file: "/tmp/test_subcmd.yaml")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_subcmd.yaml")
      end
    end

    it "loads multiple subcommands from multi-document YAML" do
      File.write("/tmp/test_multi.yaml", <<-YAML)
        ---
        name: fetch
        type: object
        properties:
          url:
            type: string
        ---
        name: save
        type: object
        properties:
          file:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi.yaml")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["url"].as_s.should eq("https://example.com")

        result = cli.parse(["save", "--file", "output.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
        result["file"].as_s.should eq("output.txt")
      ensure
        File.delete("/tmp/test_multi.yaml")
      end
    end

    it "loads multiple subcommands from relaxed JSONL" do
      File.write("/tmp/test_multi.json", <<-JSON)
        {
          "name": "fetch",
          "type": "object",
          "properties": {
            "url": {"type": "string"}
          }
        }
        {
          "name": "save",
          "type": "object",
          "properties": {
            "file": {"type": "string"}
          }
        }
        JSON
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi.json")

        result = cli.parse(["fetch", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")

        result = cli.parse(["save", "--file", "output.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
      ensure
        File.delete("/tmp/test_multi.json")
      end
    end

    it "Jargon.cli with file: auto-detects multi-doc YAML" do
      File.write("/tmp/test_subcmds.yaml", <<-YAML)
        ---
        name: run
        type: object
        properties:
          verbose:
            type: boolean
        ---
        name: build
        type: object
        properties:
          output:
            type: string
        YAML
      begin
        cli = Jargon.cli("myapp", file: "/tmp/test_subcmds.yaml")

        result = cli.parse(["run", "--verbose"])
        result.valid?.should be_true
        result.subcommand.should eq("run")
        result["verbose"].as_bool.should be_true

        result = cli.parse(["build", "--output", "dist/"])
        result.valid?.should be_true
        result.subcommand.should eq("build")
        result["output"].as_s.should eq("dist/")
      ensure
        File.delete("/tmp/test_subcmds.yaml")
      end
    end

    it "Jargon.cli with json: auto-detects multi-doc JSON" do
      json = <<-JSON
        {
          "name": "fetch",
          "type": "object",
          "properties": {"url": {"type": "string"}}
        }
        {
          "name": "save",
          "type": "object",
          "properties": {"file": {"type": "string"}}
        }
        JSON

      cli = Jargon.cli("myapp", json: json)

      result = cli.parse(["fetch", "--url", "https://example.com"])
      result.valid?.should be_true
      result.subcommand.should eq("fetch")

      result = cli.parse(["save", "--file", "out.txt"])
      result.valid?.should be_true
      result.subcommand.should eq("save")
    end

    it "Jargon.cli with yaml: auto-detects multi-doc YAML" do
      yaml = <<-YAML
        ---
        name: start
        type: object
        properties:
          port:
            type: integer
        ---
        name: stop
        type: object
        properties:
          force:
            type: boolean
        YAML

      cli = Jargon.cli("myapp", yaml: yaml)

      result = cli.parse(["start", "--port", "8080"])
      result.valid?.should be_true
      result.subcommand.should eq("start")
      result["port"].as_i64.should eq(8080)

      result = cli.parse(["stop", "--force"])
      result.valid?.should be_true
      result.subcommand.should eq("stop")
      result["force"].as_bool.should be_true
    end

    it "infers type: object when multi-doc YAML omits type but has properties" do
      yaml = <<-YAML
        ---
        name: fmt
        description: Format files
        positional: [file]
        properties:
          file:
            type: string
          output:
            type: string
            short: o
            description: Output path
        ---
        name: check
        description: Check files
        properties:
          group:
            type: string
            short: g
        YAML

      cli = Jargon.cli("myapp", yaml: yaml)

      result = cli.parse(["fmt", "in.c0", "--output", "out.c0"])
      result.valid?.should be_true
      result["output"].as_s.should eq("out.c0")

      result = cli.parse(["fmt", "in.c0", "-o", "out.c0"])
      result.valid?.should be_true
      result["output"].as_s.should eq("out.c0")

      result = cli.parse(["check", "-g", "indent"])
      result.valid?.should be_true
      result["group"].as_s.should eq("indent")

      help = cli.help("fmt")
      help.should contain("Arguments:")
      help.should contain("file")
      help.should contain("-o, --output")
    end

    it "infers type: array when type is omitted but items is present" do
      schema = Jargon::Schema.from_json(%({
        "properties": {
          "tags": {"items": {"type": "string"}}
        }
      }))
      tags = schema.root.properties.not_nil!["tags"]
      tags.type.array?.should be_true
      tags.items.not_nil!.type.string?.should be_true
    end

    it "raises when properties is present under an explicit non-object type" do
      expect_raises(ArgumentError, /type 'string' but has 'properties'/) do
        Jargon::Schema.from_json(%({
          "type": "string",
          "properties": {"name": {"type": "string"}}
        }))
      end
    end

    it "raises when items is present under an explicit non-array type" do
      expect_raises(ArgumentError, /type 'object' but has 'items'/) do
        Jargon::Schema.from_json(%({
          "type": "object",
          "items": {"type": "string"}
        }))
      end
    end

    it "loads multi-doc as nested subcommands when name provided" do
      File.write("/tmp/test_nested_multi.yaml", <<-YAML)
        ---
        name: get
        type: object
        properties:
          key:
            type: string
        ---
        name: set
        type: object
        properties:
          key:
            type: string
          value:
            type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("config", file: "/tmp/test_nested_multi.yaml")

        result = cli.parse(["config", "get", "--key", "api_url"])
        result.valid?.should be_true
        result.subcommand.should eq("config get")
        result["key"].as_s.should eq("api_url")

        result = cli.parse(["config", "set", "--key", "api_url", "--value", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("config set")
        result["key"].as_s.should eq("api_url")
        result["value"].as_s.should eq("https://example.com")
      ensure
        File.delete("/tmp/test_nested_multi.yaml")
      end
    end

    it "does not leak one subcommand's properties into others through a shared mixin" do
      cli = Jargon.cli("myapp", yaml: <<-YAML)
        ---
        $id: output
        properties:
          format: {type: string}
        required: [format]
        ---
        $id: auth
        properties:
          token: {type: string}
        required: [token]
        ---
        name: first
        allOf:
          - {$ref: output}
          - properties:
              only_first: {type: string}
        ---
        name: second
        allOf:
          - {$ref: output}
          - {$ref: auth}
        YAML

      # `only_first` was merged into `first` after `output` was referenced;
      # it must not show up in `second`, which references the same mixin.
      second = cli.subcommands["second"].as(Jargon::Schema)
      second.root.properties.not_nil!.keys.sort!.should eq(["format", "token"])
      # `required` lists from every mixin are unioned rather than the first winning.
      second.root.properties.not_nil!.values.select(&.required?).map(&.name).sort!.should eq(["format", "token"])

      cli.parse(["second", "--only_first", "x"]).valid?.should be_false
    end

    it "unions a subcommand's own required list with its mixins' required lists" do
      cli = Jargon.cli("myapp", yaml: <<-YAML)
        ---
        $id: output
        properties:
          format: {type: string}
        required: [format]
        ---
        name: report
        allOf:
          - {$ref: output}
        properties:
          title: {type: string}
        required: [title]
        YAML

      report = cli.subcommands["report"].as(Jargon::Schema)
      report.root.properties.not_nil!.values.select(&.required?).map(&.name).sort!.should eq(["format", "title"])
      cli.parse(["report", "--title", "x"]).valid?.should be_false
      cli.parse(["report", "--title", "x", "--format", "json"]).valid?.should be_true
    end

    it "supports $id mixins with $ref in allOf" do
      File.write("/tmp/test_mixin.yaml", <<-YAML)
        ---
        $id: global
        type: object
        properties:
          verbose:
            type: boolean
            short: v
          config:
            type: string
            short: c
        ---
        name: fetch
        allOf:
          - {$ref: global}
          - properties:
              url:
                type: string
        ---
        name: save
        allOf:
          - {$ref: global}
          - properties:
              file:
                type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_mixin.yaml")

        # fetch should have verbose, config, and url
        result = cli.parse(["fetch", "--verbose", "--config", "app.conf", "--url", "https://example.com"])
        result.valid?.should be_true
        result.subcommand.should eq("fetch")
        result["verbose"].as_bool.should be_true
        result["config"].as_s.should eq("app.conf")
        result["url"].as_s.should eq("https://example.com")

        # save should have verbose, config, and file
        result = cli.parse(["save", "-v", "-c", "app.conf", "--file", "out.txt"])
        result.valid?.should be_true
        result.subcommand.should eq("save")
        result["verbose"].as_bool.should be_true
        result["config"].as_s.should eq("app.conf")
        result["file"].as_s.should eq("out.txt")
      ensure
        File.delete("/tmp/test_mixin.yaml")
      end
    end

    it "supports multiple $id mixins" do
      File.write("/tmp/test_multi_mixin.yaml", <<-YAML)
        ---
        $id: global
        properties:
          verbose:
            type: boolean
            short: v
        ---
        $id: output
        properties:
          format:
            type: string
            enum: [json, yaml, csv]
        ---
        name: export
        allOf:
          - {$ref: global}
          - {$ref: output}
          - properties:
              file:
                type: string
        YAML
      begin
        cli = Jargon.new("myapp")
        cli.subcommand(file: "/tmp/test_multi_mixin.yaml")

        result = cli.parse(["export", "-v", "--format", "json", "--file", "out.txt"])
        result.valid?.should be_true
        result["verbose"].as_bool.should be_true
        result["format"].as_s.should eq("json")
        result["file"].as_s.should eq("out.txt")
      ensure
        File.delete("/tmp/test_multi_mixin.yaml")
      end
    end

    it "errors on unknown $ref" do
      File.write("/tmp/test_bad_ref.yaml", <<-YAML)
        ---
        $id: dummy
        properties:
          x: {type: string}
        ---
        name: fetch
        allOf:
          - {$ref: nonexistent}
          - properties:
              url:
                type: string
        YAML
      begin
        expect_raises(ArgumentError, /Unknown \$ref: nonexistent/) do
          cli = Jargon.new("myapp")
          cli.subcommand(file: "/tmp/test_bad_ref.yaml")
        end
      ensure
        File.delete("/tmp/test_bad_ref.yaml")
      end
    end

    it "errors when multi-doc schema missing both name and $id" do
      File.write("/tmp/test_no_name.yaml", <<-YAML)
        ---
        type: object
        properties:
          url:
            type: string
        ---
        name: save
        type: object
        properties:
          file:
            type: string
        YAML
      begin
        expect_raises(ArgumentError, /must have either 'name'.*or '\$id'/) do
          cli = Jargon.new("myapp")
          cli.subcommand(file: "/tmp/test_no_name.yaml")
        end
      ensure
        File.delete("/tmp/test_no_name.yaml")
      end
    end
  end

  describe "extension annotations (x-*)" do
    it "preserves x-* keys on properties and exposes them via extensions" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "x-ui": {"control": "typeahead", "source": "documents"}
          }
        }
      }))

      query = schema.root.properties.not_nil!["query"]
      query.extensions["x-ui"]["control"].as_s.should eq("typeahead")
      query.extensions["x-ui"]["source"].as_s.should eq("documents")
      query.extensions["ui"]?.should be_nil
    end

    it "preserves doc-level x-* keys on the root property (command annotations)" do
      yaml = <<-YAML
        ---
        name: forget
        description: Remove a document
        x-ui:
          destructive: true
        properties:
          query:
            type: string
            x-ui:
              control: typeahead
        ---
        name: add
        x-ui:
          control: dropzone
        properties:
          file:
            type: string
        YAML

      cli = Jargon.cli("transfs", yaml: yaml)

      forget = cli.subcommands["forget"].as(Jargon::Schema)
      forget.root.extensions["x-ui"]["destructive"].as_bool.should be_true
      forget.root.properties.not_nil!["query"].extensions["x-ui"]["control"].as_s.should eq("typeahead")

      add = cli.subcommands["add"].as(Jargon::Schema)
      add.root.extensions["x-ui"]["control"].as_s.should eq("dropzone")
    end

    it "ignores x-* keys for parsing and validation" do
      yaml = <<-YAML
        ---
        name: forget
        x-ui:
          destructive: true
        properties:
          query:
            type: string
            x-ui:
              control: typeahead
        ---
        name: add
        properties:
          file:
            type: string
        YAML

      cli = Jargon.cli("transfs", yaml: yaml)
      result = cli.parse(["forget", "--query", "report"])
      result.valid?.should be_true
      result["query"].as_s.should eq("report")
      result.data.as_h.has_key?("x-ui").should be_false
    end

    it "has empty extensions when no annotations exist" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {"name": {"type": "string"}}
      }))

      prop = schema.root.properties.not_nil!["name"]
      prop.extensions.empty?.should be_true
      prop.extensions["x-ui"]?.should be_nil
    end
  end

  describe "subcommand abbreviations" do
    it "matches unambiguous prefix" do
      cli = Jargon.new("myapp")
      cli.subcommand("checkout", json: %({"type": "object", "properties": {}}))
      cli.subcommand("commit", json: %({"type": "object", "properties": {}}))
      cli.subcommand("config", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["che"])
      result.valid?.should be_true
      result.subcommand.should eq("checkout")

      result = cli.parse(["comm"])
      result.valid?.should be_true
      result.subcommand.should eq("commit")

      result = cli.parse(["conf"])
      result.valid?.should be_true
      result.subcommand.should eq("config")
    end

    it "rejects abbreviations shorter than 3 characters" do
      cli = Jargon.new("myapp")
      cli.subcommand("checkout", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["ch"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: ch")

      result = cli.parse(["c"])
      result.valid?.should be_false
    end

    it "rejects ambiguous abbreviations" do
      cli = Jargon.new("myapp")
      cli.subcommand("config-get", json: %({"type": "object", "properties": {}}))
      cli.subcommand("config-set", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["config-"])
      result.valid?.should be_false
      result.errors.should contain("Unknown subcommand: config-")
    end

    it "prefers exact match over prefix" do
      cli = Jargon.new("myapp")
      cli.subcommand("test", json: %({"type": "object", "properties": {}}))
      cli.subcommand("testing", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["test"])
      result.valid?.should be_true
      result.subcommand.should eq("test")
    end

    it "works with subcommand options" do
      cli = Jargon.new("git")
      cli.subcommand("checkout", json: %({
        "type": "object",
        "positional": ["branch"],
        "properties": {
          "branch": {"type": "string"}
        }
      }))

      result = cli.parse(["che", "main"])
      result.valid?.should be_true
      result.subcommand.should eq("checkout")
      result["branch"].as_s.should eq("main")
    end
  end

  describe "help with new features" do
    it "generates help with short flags" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n", "description": "Number of items"}
        }
      }))

      help = cli.help
      help.should contain("-n, --count")
      help.should contain("Number of items")
    end

    it "generates help with positional args" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string", "description": "Input file"},
          "verbose": {"type": "boolean"}
        }
      }))

      help = cli.help
      help.should contain("Arguments:")
      help.should contain("file")
      help.should contain("Input file")
    end

    it "generates help for subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({"type": "object", "properties": {}}))
      cli.subcommand("test", json: %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("Commands:")
      help.should contain("run")
      help.should contain("test")
    end

    it "shows subcommand descriptions in the top-level command list" do
      cli = Jargon.new("myapp")
      cli.subcommand("tag", json: %({"type": "object", "description": "Attach tags", "properties": {}}))
      cli.subcommand("forget", json: %({"type": "object", "description": "Remove a document", "properties": {}}))
      cli.subcommand("ls", json: %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("tag     Attach tags")
      help.should contain("forget  Remove a document")
      # No description: bare name, no trailing padding/description.
      help.should contain("\n  ls\n")
    end

    it "shows nested subcommand descriptions" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({"type": "object", "description": "Add a remote", "properties": {}}))
      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      help = cli.help
      help.should contain("add  Add a remote")
    end
  end

  describe "stdin JSON input" do
    it "parses JSON from stdin with subcommand in JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10}
        },
        "required": ["query_text"]
      }))

      input = IO::Memory.new(%({"subcommand": "query", "query_text": "search term", "top": 5}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
      result["top"].as_i64.should eq(5)
    end

    it "parses JSON from stdin for explicit subcommand" do
      cli = Jargon.new("xerp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "properties": {
          "result_id": {"type": "string"},
          "useful": {"type": "boolean"}
        },
        "required": ["result_id"]
      }))

      input = IO::Memory.new(%({"result_id": "abc123", "useful": true}))
      result = cli.parse(["mark", "-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("mark")
      result["result_id"].as_s.should eq("abc123")
      result["useful"].as_bool.should be_true
    end

    it "uses default subcommand when not specified in JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"}
        },
        "required": ["query_text"]
      }))
      cli.default_subcommand("query")

      input = IO::Memory.new(%({"query_text": "search term"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
    end

    it "applies defaults to JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer", "default": 10}
        }
      }))

      input = IO::Memory.new(%({"query_text": "test"}))
      result = cli.parse(["query", "-"], input)

      result.valid?.should be_true
      result["top"].as_i64.should eq(10)
    end

    it "validates JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("mark", json: %({
        "type": "object",
        "properties": {
          "result_id": {"type": "string"}
        },
        "required": ["result_id"]
      }))

      input = IO::Memory.new(%({}))
      result = cli.parse(["mark", "-"], input)

      result.valid?.should be_false
      result.errors.should contain("Missing required field: result_id")
    end

    it "errors on invalid JSON" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      input = IO::Memory.new("not valid json")
      result = cli.parse(["query", "-"], input)

      result.valid?.should be_false
      result.errors.first.should contain("Invalid JSON")
    end

    it "errors when no subcommand in JSON and no default" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'subcommand' specified in JSON")
    end

    it "uses custom subcommand key" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"}
        }
      }))
      cli.subcommand_key("op")

      input = IO::Memory.new(%({"op": "query", "query_text": "search term"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_true
      result.subcommand.should eq("query")
      result["query_text"].as_s.should eq("search term")
    end

    it "errors with custom key name in message" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))
      cli.subcommand_key("op")

      input = IO::Memory.new(%({"foo": "bar"}))
      result = cli.parse(["-"], input)

      result.valid?.should be_false
      result.errors.should contain("No 'op' specified in JSON")
    end

    it "applies user defaults to stdin JSON input" do
      cli = Jargon.new("xerp")
      cli.subcommand("query", json: %({
        "type": "object",
        "properties": {
          "query_text": {"type": "string"},
          "top": {"type": "integer"}
        }
      }))

      defaults = {"top" => JSON::Any.new(25_i64)}
      input = IO::Memory.new(%({"query_text": "search"}))
      result = cli.parse(["query", "-"], input, defaults: defaults)

      result.valid?.should be_true
      result["query_text"].as_s.should eq("search")
      result["top"].as_i64.should eq(25) # From defaults
    end

    it "applies env vars to stdin JSON input" do
      ENV["TEST_STDIN_HOST"] = "env-host"
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("run", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string", "env": "TEST_STDIN_HOST"},
            "port": {"type": "integer"}
          }
        }))

        input = IO::Memory.new(%({"port": 8080}))
        result = cli.parse(["run", "-"], input)

        result.valid?.should be_true
        result["host"].as_s.should eq("env-host") # From env var
        result["port"].as_i64.should eq(8080)
      ensure
        ENV.delete("TEST_STDIN_HOST")
      end
    end

    it "stdin JSON values override defaults and env vars" do
      ENV["TEST_STDIN_PORT"] = "9000"
      begin
        cli = Jargon.new("myapp")
        cli.subcommand("run", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer", "env": "TEST_STDIN_PORT"}
          }
        }))

        defaults = {"host" => JSON::Any.new("default-host")}
        input = IO::Memory.new(%({"host": "json-host", "port": 3000}))
        result = cli.parse(["run", "-"], input, defaults: defaults)

        result.valid?.should be_true
        result["host"].as_s.should eq("json-host") # JSON wins over defaults
        result["port"].as_i64.should eq(3000)      # JSON wins over env var
      ensure
        ENV.delete("TEST_STDIN_PORT")
      end
    end
  end

  describe "nested subcommands" do
    it "parses nested subcommand" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "positional": ["name", "url"],
        "properties": {
          "name": {"type": "string"},
          "url": {"type": "string"}
        },
        "required": ["name", "url"]
      }))
      remote.subcommand("remove", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {}}))

      result = cli.parse(["remote", "add", "origin", "https://github.com/user/repo"])
      result.valid?.should be_true
      result.subcommand.should eq("remote add")
      result["name"].as_s.should eq("origin")
      result["url"].as_s.should eq("https://github.com/user/repo")
    end

    it "handles deeply nested subcommands" do
      level2 = Jargon.new("level2")
      level2.subcommand("action", json: %({
        "type": "object",
        "properties": {
          "flag": {"type": "boolean"}
        }
      }))

      level1 = Jargon.new("level1")
      level1.subcommand("level2", level2)

      cli = Jargon.new("app")
      cli.subcommand("level1", level1)

      result = cli.parse(["level1", "level2", "action", "--flag"])
      result.valid?.should be_true
      result.subcommand.should eq("level1 level2 action")
      result["flag"].as_bool.should be_true
    end

    it "mixes nested CLI and schema subcommands" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {"short": {"type": "boolean", "short": "s"}}}))

      result1 = cli.parse(["remote", "add", "name=origin"])
      result1.valid?.should be_true
      result1.subcommand.should eq("remote add")

      result2 = cli.parse(["status", "-s"])
      result2.valid?.should be_true
      result2.subcommand.should eq("status")
      result2["short"].as_bool.should be_true
    end

    it "uses default subcommand in nested CLI" do
      remote = Jargon.new("remote")
      remote.subcommand("list", json: %({"type": "object", "properties": {"verbose": {"type": "boolean"}}}))
      remote.subcommand("add", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
      remote.default_subcommand("list")

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      result = cli.parse(["remote", "--verbose"])
      result.valid?.should be_true
      result.subcommand.should eq("remote list")
      result["verbose"].as_bool.should be_true
    end

    it "validates nested subcommand data" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "properties": {"name": {"type": "string"}},
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      errors = cli.validate({"name" => JSON::Any.new("origin")}, "remote add")
      errors.should be_empty

      errors = cli.validate({} of String => JSON::Any, "remote add")
      errors.should contain("Missing required field: name")
    end

    it "shows nested commands in help" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({"type": "object", "properties": {}}))
      remote.subcommand("remove", json: %({"type": "object", "properties": {}}))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)
      cli.subcommand("status", json: %({"type": "object", "properties": {}}))

      help = cli.help
      help.should contain("remote")
      help.should contain("add")
      help.should contain("remove")
      help.should contain("status")
    end
  end

  describe "schema merge" do
    it "merges global properties into subcommand schema" do
      global = %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"},
          "config": {"type": "string", "short": "c"}
        }
      })

      sub = %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        }
      })

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["file"].should_not be_nil
      parsed["properties"]["verbose"].should_not be_nil
      parsed["properties"]["config"].should_not be_nil
    end

    it "sub properties take precedence over global" do
      global = %({
        "type": "object",
        "properties": {
          "output": {"type": "string", "default": "stdout"}
        }
      })

      sub = %({
        "type": "object",
        "properties": {
          "output": {"type": "string", "default": "file.txt"}
        }
      })

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["output"]["default"].as_s.should eq("file.txt")
    end

    it "works with CLI parsing" do
      global = %({
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean", "short": "v"}
        }
      })

      cli = Jargon.new("myapp")
      cli.subcommand("run", json: Jargon.merge(%({
        "type": "object",
        "positional": ["file"],
        "properties": {
          "file": {"type": "string"}
        }
      }), global))

      result = cli.parse(["run", "test.cr", "-v"])
      result.valid?.should be_true
      result["file"].as_s.should eq("test.cr")
      result["verbose"].as_bool.should be_true
    end

    it "handles empty properties gracefully" do
      global = %({"type": "object", "properties": {"verbose": {"type": "boolean"}}})
      sub = %({"type": "object"})

      merged = Jargon.merge(sub, global)
      parsed = JSON.parse(merged)

      parsed["properties"]["verbose"].should_not be_nil
    end
  end

  describe "automatic help detection" do
    it "detects --help in flat schema" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects -h in flat schema" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "user-defined help property takes precedence" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "help": {"type": "string"}
        }
      }))

      result = cli.parse(["--help", "topic"])
      result.help_requested?.should be_false
      result["help"].as_s.should eq("topic")
    end

    it "user-defined -h short flag takes precedence" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "host": {"type": "string", "short": "h"}
        }
      }))

      result = cli.parse(["-h", "localhost"])
      result.help_requested?.should be_false
      result["host"].as_s.should eq("localhost")
    end

    it "detects top-level --help with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects top-level -h with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should be_nil
    end

    it "detects subcommand help (query --help)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects subcommand help (query -h)" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {"text": {"type": "string"}}}))

      result = cli.parse(["query", "-h"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("query")
    end

    it "detects nested subcommand help (remote add --help)" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "url": {"type": "string"}
        }
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      result = cli.parse(["remote", "add", "--help"])
      result.help_requested?.should be_true
      result.help_subcommand.should eq("remote add")
    end

    it "cli.help(subcommand) generates correct output" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({
        "type": "object",
        "positional": ["text"],
        "properties": {
          "text": {"type": "string", "description": "Search text"},
          "limit": {"type": "integer", "short": "n", "description": "Result limit"}
        },
        "required": ["text"]
      }))

      help = cli.help("query")
      help.should contain("Usage: myapp query")
      help.should contain("<text>")
      help.should contain("Search text")
      help.should contain("-n, --limit")
      help.should contain("Result limit")
    end

    it "cli.help(subcommand) works for nested subcommands" do
      remote = Jargon.new("remote")
      remote.subcommand("add", json: %({
        "type": "object",
        "positional": ["name"],
        "properties": {
          "name": {"type": "string", "description": "Remote name"}
        },
        "required": ["name"]
      }))

      cli = Jargon.new("git")
      cli.subcommand("remote", remote)

      help = cli.help("remote add")
      help.should contain("Usage: remote add")
      help.should contain("<name>")
      help.should contain("Remote name")
    end

    it "cli.help(subcommand) returns error for unknown subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("query", json: %({"type": "object", "properties": {}}))

      help = cli.help("unknown")
      help.should contain("Unknown subcommand: unknown")
    end

    it "help_requested is false when not requested" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["name=test"])
      result.help_requested?.should be_false
    end
  end

  describe "public validate method" do
    it "validates data hash directly" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "count": {"type": "integer"}
        },
        "required": ["name"]
      }))

      errors = cli.validate({"count" => JSON::Any.new(42_i64)})
      errors.should contain("Missing required field: name")
    end

    it "returns empty array for valid data" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      errors = cli.validate({"name" => JSON::Any.new("John")})
      errors.should be_empty
    end

    it "validates result object" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }))

      result = cli.parse(["name=John"])
      errors = cli.validate(result)
      errors.should be_empty
    end

    it "validates subcommand data with subcommand name" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        },
        "required": ["file"]
      }))

      errors = cli.validate({} of String => JSON::Any, "run")
      errors.should contain("Missing required field: file")
    end

    it "validates result from subcommand" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "file": {"type": "string"}
        },
        "required": ["file"]
      }))

      result = cli.parse(["run", "file=test.cr"])
      errors = cli.validate(result)
      errors.should be_empty
    end
  end

  describe "additionalProperties" do
    it "allows unknown keys by default (additionalProperties absent)" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      data = {"name" => JSON::Any.new("Alice"), "extra" => JSON::Any.new("value")}
      errors = Jargon::Validator.validate(data, schema)
      errors.should be_empty
    end

    it "allows unknown keys when additionalProperties is true" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "additionalProperties": true,
        "properties": {
          "name": {"type": "string"}
        }
      }))

      data = {"name" => JSON::Any.new("Alice"), "extra" => JSON::Any.new("value")}
      errors = Jargon::Validator.validate(data, schema)
      errors.should be_empty
    end

    it "rejects unknown keys when additionalProperties is false" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"}
        }
      }))

      data = {"name" => JSON::Any.new("Alice"), "unknown" => JSON::Any.new("bad")}
      errors = Jargon::Validator.validate(data, schema)
      errors.size.should eq(1)
      errors.first.should contain("Unknown property 'unknown'")
      errors.first.should contain("additionalProperties is false")
    end

    it "reports multiple unknown keys" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string"}
        }
      }))

      data = {"name" => JSON::Any.new("Alice"), "foo" => JSON::Any.new("a"), "bar" => JSON::Any.new("b")}
      errors = Jargon::Validator.validate(data, schema)
      errors.size.should eq(2)
    end

    it "passes when all keys are known and additionalProperties is false" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"}
        }
      }))

      data = {"name" => JSON::Any.new("Alice"), "age" => JSON::Any.new(30_i64)}
      errors = Jargon::Validator.validate(data, schema)
      errors.should be_empty
    end

    it "works on nested objects" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "user": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "name": {"type": "string"}
            }
          }
        }
      }))

      data = {"user" => JSON::Any.new({"name" => JSON::Any.new("Alice"), "extra" => JSON::Any.new("bad")})}
      errors = Jargon::Validator.validate(data, schema)
      errors.size.should eq(1)
      errors.first.should contain("Unknown property 'user.extra'")
    end

    it "works via CLI parse" do
      cli = Jargon.cli("myapp", json: %({
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string"},
          "verbose": {"type": "boolean"}
        }
      }))

      result = cli.parse(["--name", "Alice", "--verbose"])
      result.valid?.should be_true

      # Stdin JSON can introduce unknown keys
      input = IO::Memory.new(%({"name": "Alice", "unknown": "bad"}))
      result = cli.parse(["-"], input)
      result.valid?.should be_false
      result.errors.first.should contain("Unknown property 'unknown'")
    end
  end

  describe "Jargon::Validator" do
    it "validates data directly against a schema" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer"}
        },
        "required": ["name"]
      }))

      errors = Jargon::Validator.validate({"name" => JSON::Any.new("Alice")} of String => JSON::Any, schema)
      errors.should be_empty
    end

    it "returns errors for invalid data" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "age": {"type": "integer", "minimum": 0}
        },
        "required": ["name"]
      }))

      errors = Jargon::Validator.validate({} of String => JSON::Any, schema)
      errors.should contain("Missing required field: name")
    end

    it "validates numeric constraints" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "port": {"type": "integer", "minimum": 1, "maximum": 65535}
        }
      }))

      errors = Jargon::Validator.validate({"port" => JSON::Any.new(0_i64)}, schema)
      errors.size.should eq(1)
      errors.first.should contain("must be >= 1")
    end

    it "validates enum constraints" do
      schema = Jargon::Schema.from_json(%({
        "type": "object",
        "properties": {
          "level": {"type": "string", "enum": ["info", "warn", "error"]}
        }
      }))

      errors = Jargon::Validator.validate({"level" => JSON::Any.new("debug")}, schema)
      errors.size.should eq(1)
      errors.first.should contain("must be one of")
    end
  end

  describe "shell completion" do
    # The candidates engine is what each shell's shim calls at runtime.
    # words[0] is the program name; cword is the index of the word under the
    # cursor (== words.size when completing a fresh trailing token).
    describe "candidates engine" do
      it "completes long flag names from a flat schema" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "verbose": {"type": "boolean", "short": "v"}
          }
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "--"], 1).should eq(["--help", "--name", "--verbose"])
      end

      it "completes short and long flag names when partial is a single dash" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {"verbose": {"type": "boolean", "short": "v"}}
        }))
        c = Jargon::Completion.new(cli)
        candidates = c.candidates(["myapp", "-"], 1)
        candidates.should contain("-v")
        candidates.should contain("--verbose")
        candidates.should contain("-h")
      end

      it "filters flag names by the typed prefix" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {"name": {"type": "string"}, "number": {"type": "integer"}}
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "--na"], 1).should eq(["--name"])
      end

      it "excludes positional fields from flag-name candidates" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "positional": ["file"],
          "properties": {
            "file": {"type": "string"},
            "verbose": {"type": "boolean", "short": "v"}
          }
        }))
        c = Jargon::Completion.new(cli)
        candidates = c.candidates(["myapp", "--"], 1)
        candidates.should contain("--verbose")
        candidates.should_not contain("--file")
      end

      it "completes enum values for a flag (string and numeric)" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "format": {"type": "string", "enum": ["json", "yaml", "xml"]},
            "level": {"type": "integer", "enum": [1, 2, 3]}
          }
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "--format", ""], 2).should eq(["json", "yaml", "xml"])
        c.candidates(["myapp", "--format", "y"], 2).should eq(["yaml"])
        c.candidates(["myapp", "--level", ""], 2).should eq(["1", "2", "3"])
      end

      it "lists and filters subcommands at the first position" do
        cli = Jargon.new("git")
        cli.subcommand("fetch", json: %({"type": "object", "properties": {}}))
        cli.subcommand("save", json: %({"type": "object", "properties": {}}))
        c = Jargon::Completion.new(cli)
        c.candidates(["git", ""], 1).should eq(["fetch", "save"])
        c.candidates(["git", "fe"], 1).should eq(["fetch"])
      end

      it "completes flags within a chosen subcommand" do
        cli = Jargon.new("git")
        cli.subcommand("fetch", json: %({
          "type": "object",
          "properties": {"url": {"type": "string"}, "depth": {"type": "integer", "short": "d"}}
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["git", "fetch", "--"], 2).should eq(["--help", "--url", "--depth"])
      end

      it "completes flags within a nested subcommand CLI" do
        remote = Jargon.new("remote")
        remote.subcommand("add", json: %({
          "type": "object", "properties": {"name": {"type": "string"}, "url": {"type": "string"}}
        }))
        cli = Jargon.new("git")
        cli.subcommand("remote", remote)
        c = Jargon::Completion.new(cli)
        c.candidates(["git", "remote", ""], 2).should eq(["add"])
        c.candidates(["git", "remote", "add", "--"], 3).should eq(["--help", "--name", "--url"])
      end

      it "returns nothing for a flag value with no enum or completer" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object", "properties": {"name": {"type": "string"}}
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "--name", ""], 2).should eq([] of String)
      end

      it "counts a colon-bearing operand as a filled positional slot" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "positional": ["src", "mode"],
          "properties": {
            "src": {"type": "string"},
            "mode": {"type": "string", "enum": ["fast", "safe"]}
          }
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "host:8080", ""], 2).should eq(["fast", "safe"])
      end

      positional_pair = %({
        "type": "object",
        "positional": ["a", "b"],
        "properties": {
          "a": {"type": "string"},
          "b": {"type": "string", "enum": ["b1"]},
          "mode": {"type": "string", "enum": ["fast", "safe"]}
        }
      })

      it "fills positional slots with k=v and negative-number words, as the parser does" do
        c = Jargon::Completion.new(Jargon.cli("myapp", json: positional_pair))
        c.candidates(["myapp", "x=1", ""], 2).should eq(["b1"])
        c.candidates(["myapp", "-5", ""], 2).should eq(["b1"])
      end

      it "treats words after -- as operands, not flags" do
        c = Jargon::Completion.new(Jargon.cli("myapp", json: positional_pair))
        c.candidates(["myapp", "--", "-x", ""], 3).should eq(["b1"])
      end

      it "completes the value half of a --flag=value word" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "mode": {"type": "string", "enum": ["fast", "safe"]},
            "verbose": {"type": "boolean"}
          }
        }))
        c = Jargon::Completion.new(cli)
        c.candidates(["myapp", "--mode=f"], 1).should eq(["--mode=fast"])
        c.candidates(["myapp", "--mode="], 1).should eq(["--mode=fast", "--mode=safe"])
        c.candidates(["myapp", "--verbose="], 1).should eq([] of String)
      end

      it "does not read the word after --flag=value as that flag's value" do
        c = Jargon::Completion.new(Jargon.cli("myapp", json: positional_pair))
        c.candidates(["myapp", "--mode=fast", ""], 2).should eq([] of String) # slot a: no enum
        c.candidates(["myapp", "--mode=fast", "x", ""], 3).should eq(["b1"])
      end
    end

    describe "dynamic completers" do
      it "invokes a registered completer for a positional, passing the partial" do
        cli = Jargon.cli("app", json: %({
          "type": "object",
          "positional": ["query"],
          "properties": {"query": {"type": "string"}}
        }))
        cli.completer("query") { |ctx| ["doc-#{ctx.partial}-1", "doc-#{ctx.partial}-2"] }
        c = Jargon::Completion.new(cli)
        c.candidates(["app", "rep"], 1).should eq(["doc-rep-1", "doc-rep-2"])
      end

      it "invokes a registered completer for a flag value" do
        cli = Jargon.cli("app", json: %({
          "type": "object",
          "properties": {"out": {"type": "string"}}
        }))
        cli.completer("out") { |_ctx| ["a.txt", "b.txt"] }
        c = Jargon::Completion.new(cli)
        c.candidates(["app", "--out", ""], 2).should eq(["a.txt", "b.txt"])
      end

      it "passes only the value half of --flag=value to a completer" do
        cli = Jargon.cli("app", json: %({
          "type": "object",
          "properties": {"out": {"type": "string"}}
        }))
        cli.completer("out") { |ctx| ["#{ctx.partial}.txt"] }
        c = Jargon::Completion.new(cli)
        c.candidates(["app", "--out=rep"], 1).should eq(["--out=rep.txt"])
      end

      it "invokes a completer scoped to a subcommand field" do
        cli = Jargon.new("git")
        cli.subcommand("fetch", json: %({
          "type": "object", "positional": ["url"], "properties": {"url": {"type": "string"}}
        }))
        cli.completer("fetch.url") { |ctx| ["https://#{ctx.partial}.example"] }
        c = Jargon::Completion.new(cli)
        c.candidates(["git", "fetch", "site"], 2).should eq(["https://site.example"])
      end

      it "exposes subcommand and prior arguments on the context" do
        cli = Jargon.new("app")
        cli.subcommand("tag", json: %({
          "type": "object",
          "positional": ["name"],
          "properties": {"name": {"type": "string"}, "project": {"type": "string"}}
        }))
        seen_subcommand = nil
        seen_project = nil
        cli.completer("tag.name") do |ctx|
          seen_subcommand = ctx.subcommand
          seen_project = ctx.arguments["project"]?
          [] of String
        end
        Jargon::Completion.new(cli).candidates(["app", "tag", "--project", "acme", "na"], 4)
        seen_subcommand.should eq("tag")
        seen_project.should eq("acme")
      end

      it "raises when a completer path does not match a schema field" do
        cli = Jargon.cli("app", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
        expect_raises(ArgumentError, /does not match any field/) do
          cli.completer("nope") { |_ctx| [] of String }
        end
      end

      it "raises when a subcommand-scoped completer path is wrong" do
        cli = Jargon.new("git")
        cli.subcommand("fetch", json: %({"type": "object", "properties": {"url": {"type": "string"}}}))
        expect_raises(ArgumentError, /does not match any field/) do
          cli.completer("fetch.bogus") { |_ctx| [] of String }
        end
      end
    end

    # The generated scripts are thin shims that forward (cursor, words) to the
    # program's hidden __complete verb — they carry no schema knowledge.
    describe "shim generation" do
      it "generates a bash shim that calls back via __complete" do
        cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
        bash = cli.bash_completion
        bash.should contain("_myapp_complete")
        bash.should contain(%(myapp __complete "$cword" "${words[@]}"))
        bash.should contain("COMP_WORDBREAKS")
        bash.should contain("complete -F _myapp_complete myapp")
      end

      it "bash shim rejoins words split at = and : and trims candidates to match" do
        bash = Process.find_executable("bash")
        next unless bash # the shim logic needs a real bash to run

        cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {"mode": {"type": "string"}}}))
        # Stand-in for the program: log what it was called with, and offer one
        # candidate extending the word under the cursor.
        script = <<-SH
          #{cli.bash_completion}
          myapp() { echo "called: $*" >&2; local -a w=("${@:3}"); echo "${w[$2]}X"; }
          try() { COMPREPLY=(); _myapp_complete; echo "reply: ${COMPREPLY[*]}" >&2; }
          COMP_WORDBREAKS=$' \\t\\n"\\'><=;|&(:'
          COMP_LINE='myapp --mode=f'; COMP_WORDS=(myapp --mode = f); COMP_CWORD=3; try
          COMP_LINE='myapp --mode='; COMP_WORDS=(myapp --mode =); COMP_CWORD=2; try
          COMP_LINE='myapp Expenses:Fo'; COMP_WORDS=(myapp Expenses : Fo); COMP_CWORD=3; try
          COMP_LINE='myapp a : b'; COMP_WORDS=(myapp a : b); COMP_CWORD=3; try
          COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
          COMP_LINE='myapp Expenses:Fo'; COMP_WORDS=(myapp Expenses:Fo); COMP_CWORD=1; try
          SH
        err = IO::Memory.new
        Process.run(bash, ["-c", script], error: err).success?.should be_true
        err.to_s.lines.should eq([
          "called: __complete 1 myapp --mode=f", "reply: fX",
          "called: __complete 1 myapp --mode=", "reply: X",
          "called: __complete 1 myapp Expenses:Fo", "reply: FoX",
          "called: __complete 3 myapp a : b", "reply: bX",
          "called: __complete 1 myapp Expenses:Fo", "reply: Expenses:FoX",
        ])
      end

      it "quotes a program name or command that isn't a plain word" do
        cli = Jargon.cli("my app", json: %({"type": "object", "properties": {"q": {"type": "string"}}}))
        cli.bash_completion(command: "/opt/My Tools/app").should contain("'/opt/My Tools/app' __complete")
        cli.bash_completion.should contain("complete -F _my_app_complete 'my app'")

        zsh = cli.zsh_completion(command: "it's")
        zsh.should contain(%q('it'\''s' __complete))
        zsh.should contain("compdef _my_app 'my app'")
        zsh.should_not contain("#compdef") # compinit can't parse a quoted name

        cli.fish_completion(command: %q(a\b'c)).should contain(%q('a\\b\'c' __complete))
        cli.fish_completion.should contain("complete -c 'my app' -f")
      end

      it "generates a zsh shim that calls back via __complete" do
        cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
        zsh = cli.zsh_completion
        zsh.should contain("#compdef myapp")
        zsh.should contain("myapp __complete")
        zsh.should contain("compdef _myapp myapp")
      end

      it "generates a fish shim that calls back via __complete" do
        cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
        fish = cli.fish_completion
        fish.should contain("complete -c myapp -f")
        fish.should contain("myapp __complete")
        fish.should contain("commandline")
      end

      it "points the shim at a configurable target command" do
        cli = Jargon.cli("transfs", json: %({"type": "object", "properties": {"q": {"type": "string"}}}))
        cli.bash_completion(command: "transfs-complete").should contain("transfs-complete __complete")
        cli.zsh_completion(command: "transfs-complete").should contain("transfs-complete __complete")
        cli.fish_completion(command: "transfs-complete").should contain("transfs-complete __complete")
      end
    end

    describe "handle_completion dispatch" do
      it "answers the __complete verb by printing candidates" do
        cli = Jargon.cli("app", json: %({
          "type": "object", "properties": {"name": {"type": "string"}, "number": {"type": "integer"}}
        }))
        io = IO::Memory.new
        handled = cli.handle_completion(["__complete", "1", "app", "--n"], io: io, exit_process: false)
        handled.should be_true
        io.to_s.lines.should eq(["--name", "--number"])
      end

      it "routes the __complete verb to a dynamic completer" do
        cli = Jargon.cli("app", json: %({
          "type": "object", "positional": ["query"], "properties": {"query": {"type": "string"}}
        }))
        cli.completer("query") { |ctx| ["hit:#{ctx.partial}"] }
        io = IO::Memory.new
        cli.handle_completion(["__complete", "1", "app", "foo"], io: io, exit_process: false)
        io.to_s.lines.should eq(["hit:foo"])
      end

      it "returns false and does nothing for a normal invocation" do
        cli = Jargon.cli("app", json: %({"type": "object", "properties": {"name": {"type": "string"}}}))
        io = IO::Memory.new
        cli.handle_completion(["--name", "value"], io: io, exit_process: false).should be_false
        io.to_s.should eq("")
      end
    end

    describe "--completions flag" do
      it "detects --completions bash in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "bash"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("bash")
      end

      it "detects --completions zsh in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "zsh"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("zsh")
      end

      it "detects --completions fish in flat CLI" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["--completions", "fish"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("fish")
      end

      it "detects --completions in CLI with subcommands" do
        cli = Jargon.new("myapp")
        cli.subcommand("query", json: %({"type": "object", "properties": {}}))

        result = cli.parse(["--completions", "bash"])
        result.completion_requested?.should be_true
        result.completion_shell.should eq("bash")
      end

      it "errors on unknown shell" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {}
        }))

        result = cli.parse(["--completions", "powershell"])
        result.completion_requested?.should be_false
        result.valid?.should be_false
        result.errors.first.should contain("Unknown shell")
        result.errors.first.should contain("powershell")
      end

      it "completion_requested? is false when not requested" do
        cli = Jargon.cli("myapp", json: %({
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }))

        result = cli.parse(["name=test"])
        result.completion_requested?.should be_false
        result.completion_shell.should be_nil
      end
    end
  end

  describe "load_config" do
    it "searches only user config paths by default" do
      cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {}}))
      paths = cli.config_paths

      paths.size.should eq(6)
      paths.none?(&.starts_with?("./")).should be_true
      paths[0].should contain("myapp.yaml")
      paths[3].should contain("myapp/config.yaml")
    end

    it "returns config_paths in correct order with project: true" do
      cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {}}))
      paths = cli.config_paths(project: true)

      # Project local paths first (yaml, yml, json for each base)
      paths[0].should eq("./.config/myapp.yaml")
      paths[1].should eq("./.config/myapp.yml")
      paths[2].should eq("./.config/myapp.json")
      paths[3].should eq("./.config/myapp/config.yaml")
      paths[4].should eq("./.config/myapp/config.yml")
      paths[5].should eq("./.config/myapp/config.json")
      # User global paths
      paths[6].should contain("myapp.yaml")
      paths[9].should contain("myapp/config.yaml")
    end

    it "ignores an empty or relative XDG_CONFIG_HOME, per the XDG spec" do
      original = ENV["XDG_CONFIG_HOME"]?
      cli = Jargon.cli("myapp", json: %({"type": "object", "properties": {}}))
      fallback = Path.home.join(".config", "myapp.yaml").to_s

      begin
        ENV["XDG_CONFIG_HOME"] = ""
        cli.config_paths[0].should eq(fallback)
        ENV["XDG_CONFIG_HOME"] = "relative/dir"
        cli.config_paths[0].should eq(fallback)
        ENV["XDG_CONFIG_HOME"] = "/abs/xdg"
        cli.config_paths[0].should eq("/abs/xdg/myapp.yaml")
      ensure
        ENV["XDG_CONFIG_HOME"] = original
      end
    end

    it "treats a non-mapping config as invalid and an empty one as absent" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testlist.yaml", "- a\n- b\n")
      File.write("./.config/testempty.yaml", "")

      begin
        Jargon.config_warnings = false # Suppress the non-mapping warning
        schema = %({"type": "object", "properties": {}})
        Jargon.cli("testlist", json: schema).load_config(merge: false, project: true).should be_nil
        Jargon.cli("testempty", json: schema).load_config(merge: false, project: true).should be_nil
      ensure
        Jargon.config_warnings = true
        File.delete("./.config/testlist.yaml")
        File.delete("./.config/testempty.yaml")
      end
    end

    it "loads JSON config from project .config directory" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp.json", %({"host": "from-config", "port": 9000}))

      begin
        cli = Jargon.cli("testapp", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"}
          }
        }))

        config = cli.load_config(project: true)
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("from-config")
        config.not_nil!["port"].as_i.should eq(9000)
      ensure
        File.delete("./.config/testapp.json")
      end
    end

    it "loads YAML config from project .config directory" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testyaml.yaml", "host: yaml-host\nport: 8080\ndebug: true")

      begin
        cli = Jargon.cli("testyaml", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"},
            "debug": {"type": "boolean"}
          }
        }))

        config = cli.load_config(project: true)
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("yaml-host")
        config.not_nil!["port"].as_i.should eq(8080)
        config.not_nil!["debug"].as_bool.should be_true
      ensure
        File.delete("./.config/testyaml.yaml")
      end
    end

    it "prefers YAML over JSON when both exist" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testboth.yaml", "source: yaml")
      File.write("./.config/testboth.json", %({"source": "json"}))

      begin
        cli = Jargon.cli("testboth", json: %({
          "type": "object",
          "properties": {
            "source": {"type": "string"}
          }
        }))

        config = cli.load_config(merge: false, project: true)
        config.should_not be_nil
        config.not_nil!["source"].as_s.should eq("yaml")
      ensure
        File.delete("./.config/testboth.yaml")
        File.delete("./.config/testboth.json")
      end
    end

    it "returns nil when no config found" do
      cli = Jargon.cli("nonexistent-app-xyz", json: %({"type": "object", "properties": {}}))
      cli.load_config.should be_nil
    end

    it "integrates with defaults parameter" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp2.json", %({"verbose": true, "count": 5}))

      begin
        cli = Jargon.cli("testapp2", json: %({
          "type": "object",
          "properties": {
            "verbose": {"type": "boolean"},
            "count": {"type": "integer"}
          }
        }))

        config = cli.load_config(project: true)
        result = cli.parse(["--count", "10"], defaults: config)

        result["verbose"].as_bool.should be_true # From config
        result["count"].as_i64.should eq(10)     # CLI overrides
      ensure
        File.delete("./.config/testapp2.json")
      end
    end

    it "merges configs with merge: true (project wins)" do
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s

      # Create user config
      Dir.mkdir_p("#{xdg_config}/testapp3")
      File.write("#{xdg_config}/testapp3/config.json", %({"host": "user-host", "port": 8080, "user_only": "yes"}))

      # Create project config (should override user for shared keys)
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp3.json", %({"host": "project-host", "project_only": "yes"}))

      begin
        cli = Jargon.cli("testapp3", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer"},
            "user_only": {"type": "string"},
            "project_only": {"type": "string"}
          }
        }))

        config = cli.load_config(merge: true, project: true)
        config.should_not be_nil
        config.not_nil!["host"].as_s.should eq("project-host") # Project wins
        config.not_nil!["port"].as_i.should eq(8080)           # From user
        config.not_nil!["user_only"].as_s.should eq("yes")     # From user
        config.not_nil!["project_only"].as_s.should eq("yes")  # From project
      ensure
        File.delete("./.config/testapp3.json")
        File.delete("#{xdg_config}/testapp3/config.json")
        Dir.delete("#{xdg_config}/testapp3") rescue nil
      end
    end

    it "deep merges nested objects in configs" do
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s

      # Create user config with nested object
      Dir.mkdir_p("#{xdg_config}/testapp4")
      File.write("#{xdg_config}/testapp4/config.json", %({
        "database": {"host": "localhost", "port": 5432, "user": "default_user"}
      }))

      # Create project config that overrides only some nested keys
      Dir.mkdir_p("./.config")
      File.write("./.config/testapp4.json", %({
        "database": {"host": "production.example.com"}
      }))

      begin
        cli = Jargon.cli("testapp4", json: %({"type": "object", "properties": {}}))

        config = cli.load_config(merge: true, project: true)
        config.should_not be_nil
        db = config.not_nil!["database"]
        db["host"].as_s.should eq("production.example.com") # Project wins
        db["port"].as_i.should eq(5432)                     # Preserved from user
        db["user"].as_s.should eq("default_user")           # Preserved from user
      ensure
        File.delete("./.config/testapp4.json")
        File.delete("#{xdg_config}/testapp4/config.json")
        Dir.delete("#{xdg_config}/testapp4") rescue nil
      end
    end

    it "ignores project-local configs unless project: true" do
      xdg_config = ENV["XDG_CONFIG_HOME"]? || Path.home.join(".config").to_s
      Dir.mkdir_p("#{xdg_config}/testoptin")
      File.write("#{xdg_config}/testoptin/config.json", %({"host": "user-host"}))
      Dir.mkdir_p("./.config")
      File.write("./.config/testoptin.json", %({"host": "project-host"}))
      File.write("./.config/testprojonly.json", %({"host": "project-host"}))

      begin
        schema = %({"type": "object", "properties": {"host": {"type": "string"}}})
        cli = Jargon.cli("testoptin", json: schema)
        cli.load_config.not_nil!["host"].as_s.should eq("user-host")
        cli.load_config(merge: false).not_nil!["host"].as_s.should eq("user-host")
        cli.load_config(project: true).not_nil!["host"].as_s.should eq("project-host")

        Jargon.cli("testprojonly", json: schema).load_config.should be_nil
      ensure
        File.delete("./.config/testoptin.json")
        File.delete("./.config/testprojonly.json")
        File.delete("#{xdg_config}/testoptin/config.json")
        Dir.delete("#{xdg_config}/testoptin") rescue nil
      end
    end
  end

  describe "defaults parameter" do
    it "uses defaults when CLI arg not provided" do
      cli = Jargon.cli("testbad", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "verbose": {"type": "boolean"}
        }
      }))

      defaults = {"name" => JSON::Any.new("default-name"), "verbose" => JSON::Any.new(true)}
      result = cli.parse([] of String, defaults: defaults)

      result.valid?.should be_true
      result["name"].as_s.should eq("default-name")
      result["verbose"].as_bool.should be_true
    end

    it "CLI args override defaults" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }))

      defaults = {"name" => JSON::Any.new("from-config")}
      result = cli.parse(["--name", "from-cli"], defaults: defaults)

      result["name"].as_s.should eq("from-cli")
    end

    it "works with JSON::Any from parsed JSON" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "output": {"type": "string"},
          "count": {"type": "integer"}
        }
      }))

      config_json = JSON.parse(%({"output": "default.txt", "count": 10}))
      result = cli.parse(["--count", "5"], defaults: config_json)

      result["output"].as_s.should eq("default.txt")
      result["count"].as_i64.should eq(5) # CLI overrides
    end

    it "schema defaults fill remaining gaps" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "host": {"type": "string", "default": "localhost"},
          "port": {"type": "integer", "default": 8080},
          "debug": {"type": "boolean"}
        }
      }))

      # User defaults override schema default for port
      # Schema default for host fills remaining gap
      defaults = {"port" => JSON::Any.new(3000_i64), "debug" => JSON::Any.new(true)}
      result = cli.parse([] of String, defaults: defaults)

      result["host"].as_s.should eq("localhost") # Schema default
      result["port"].as_i64.should eq(3000)      # User default
      result["debug"].as_bool.should be_true     # User default
    end

    it "works with subcommands" do
      cli = Jargon.new("myapp")
      cli.subcommand("run", json: %({
        "type": "object",
        "properties": {
          "env": {"type": "string"}
        }
      }))

      defaults = {"env" => JSON::Any.new("production")}
      result = cli.parse(["run"], defaults: defaults)

      result.subcommand.should eq("run")
      result["env"].as_s.should eq("production")
    end

    server_schema = %({
      "type": "object",
      "properties": {
        "server": {
          "type": "object",
          "properties": {
            "host": {"type": "string"},
            "port": {"type": "integer", "default": 80}
          }
        }
      }
    })

    it "fills nested objects key by key, so a CLI value keeps sibling defaults" do
      cli = Jargon.cli("app", json: server_schema)
      result = cli.parse(["--server.port", "1"], defaults: JSON.parse(%({"server": {"host": "cfg"}})))

      result["server"]["host"].as_s.should eq("cfg")
      result["server"]["port"].as_i64.should eq(1)
    end

    it "never mutates the caller's defaults" do
      cli = Jargon.cli("app", json: server_schema)
      defaults = JSON.parse(%({"server": {"host": "cfg"}}))
      result = cli.parse([] of String, defaults: defaults)

      result["server"]["port"].as_i64.should eq(80)
      defaults.to_json.should eq(%({"server":{"host":"cfg"}}))
    end

    it "does not share schema defaults between results" do
      cli = Jargon.cli("app", json: %({
        "type": "object",
        "properties": {"tags": {"type": "array", "default": ["a"]}}
      }))

      cli.parse([] of String)["tags"].as_a << JSON::Any.new("b")
      cli.parse([] of String)["tags"].as_a.map(&.as_s).should eq(["a"])
    end

    it "raises ArgumentError for defaults that aren't an object" do
      cli = Jargon.cli("app", json: server_schema)
      expect_raises(ArgumentError, "defaults must be a JSON object") do
        cli.parse([] of String, defaults: JSON.parse(%(["a"])))
      end
    end
  end

  describe "error handling edge cases" do
    it "handles invalid integer coercion with clear error" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"}
        }
      }))

      result = cli.parse(["--count", "abc"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid integer value 'abc' for count")
    end

    it "handles invalid number coercion with clear error" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--rate", "not-a-number"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid number value 'not-a-number' for rate")
    end

    it "rejects partial numeric values like '10x'" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--count", "10x"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid integer value '10x' for count")

      result = cli.parse(["--rate", "3.14abc"])
      result.valid?.should be_false
      result.errors.first.should contain("Invalid number value '3.14abc' for rate")
    end

    it "errors on missing value for non-boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "name": {"type": "string"}
        }
      }))

      result = cli.parse(["--count"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --count")

      result = cli.parse(["--name"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --name")
    end

    it "errors on missing value for short non-boolean flag" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer", "short": "n"}
        }
      }))

      result = cli.parse(["-n"])
      result.valid?.should be_false
      result.errors.should contain("Missing value for --count")
    end

    it "parses negative numbers as values" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "count": {"type": "integer"},
          "rate": {"type": "number"}
        }
      }))

      result = cli.parse(["--count", "-5"])
      result.valid?.should be_true
      result["count"].as_i64.should eq(-5)

      result = cli.parse(["--rate", "-3.14"])
      result.valid?.should be_true
      result["rate"].as_f.should eq(-3.14)
    end

    it "handles malformed JSON config file gracefully" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testbad.json", "{ invalid json }")

      begin
        Jargon.config_warnings = false # Suppress warning during test
        cli = Jargon.cli("testbad", json: %({"type": "object", "properties": {}}))
        # Returns nil and prints warning to STDERR (suppressed here)
        config = cli.load_config(project: true)
        config.should be_nil
      ensure
        Jargon.config_warnings = true
        File.delete("./.config/testbad.json")
      end
    end

    it "handles malformed YAML config file gracefully" do
      Dir.mkdir_p("./.config")
      File.write("./.config/testbadyaml.yaml", "invalid: yaml: content: [")

      begin
        Jargon.config_warnings = false # Suppress warning during test
        cli = Jargon.cli("testbadyaml", json: %({"type": "object", "properties": {}}))
        # Returns nil and prints warning to STDERR (suppressed here)
        config = cli.load_config(project: true)
        config.should be_nil
      ensure
        Jargon.config_warnings = true
        File.delete("./.config/testbadyaml.yaml")
      end
    end
  end

  describe "nested object defaults" do
    it "applies defaults to nested objects" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "server": {
            "type": "object",
            "properties": {
              "host": {"type": "string", "default": "localhost"},
              "port": {"type": "integer", "default": 8080}
            }
          }
        }
      }))

      result = cli.parse(["server.host=example.com"])
      result.valid?.should be_true
      result["server"]["host"].as_s.should eq("example.com")
      result["server"]["port"].as_i64.should eq(8080) # Default applied
    end
  end

  describe "$ref edge cases" do
    it "handles missing $ref target gracefully" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {"$ref": "#/$defs/nonexistent"}
        },
        "$defs": {}
      }))

      # Should not crash, just treat as unresolved
      result = cli.parse(["user.name=test"])
      result.valid?.should be_false
    end

    it "handles invalid $ref format gracefully" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "user": {"$ref": "invalid-ref-format"}
        }
      }))

      # Should not crash
      result = cli.parse([] of String)
      result.valid?.should be_true
    end

    recursive_schema = %({
      "type": "object",
      "$defs": {
        "Node": {
          "type": "object",
          "default": {},
          "properties": {
            "child": {"$ref": "#/$defs/Node"},
            "name": {"type": "string"}
          }
        }
      },
      "properties": {"root": {"$ref": "#/$defs/Node"}}
    })

    it "lists a recursive $ref in help without expanding it forever" do
      help = Jargon.cli("cli", json: recursive_schema).help
      help.should contain("--root.child=<object>")
      help.should contain("--root.name=<string>")
      help.should_not contain("--root.child.name")
    end

    it "applies defaults through a recursive $ref without nesting forever" do
      cli = Jargon.cli("cli", json: recursive_schema)
      cli.parse([] of String).data.to_json.should eq(%({"root":{}}))

      result = cli.parse(["--root.child.child.name", "leaf"])
      result.valid?.should be_true
      result["root"]["child"]["child"]["name"].as_s.should eq("leaf")
    end
  end

  describe "environment variables" do
    it "uses env var when CLI arg not provided" do
      ENV["TEST_JARGON_HOST"] = "env-host"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "host": {"type": "string", "env": "TEST_JARGON_HOST"}
          }
        }))

        result = cli.parse([] of String)
        result["host"].as_s.should eq("env-host")
      ensure
        ENV.delete("TEST_JARGON_HOST")
      end
    end

    it "CLI args override env vars" do
      ENV["TEST_JARGON_PORT"] = "8080"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "port": {"type": "integer", "env": "TEST_JARGON_PORT"}
          }
        }))

        result = cli.parse(["--port", "3000"])
        result["port"].as_i64.should eq(3000)
      ensure
        ENV.delete("TEST_JARGON_PORT")
      end
    end

    it "env vars override config defaults" do
      ENV["TEST_JARGON_DEBUG"] = "true"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "debug": {"type": "boolean", "env": "TEST_JARGON_DEBUG"}
          }
        }))

        config = {"debug" => JSON::Any.new(false)}
        result = cli.parse([] of String, defaults: config)
        result["debug"].as_bool.should be_true
      ensure
        ENV.delete("TEST_JARGON_DEBUG")
      end
    end

    it "coerces env var values to correct types" do
      ENV["TEST_JARGON_COUNT"] = "42"
      ENV["TEST_JARGON_ENABLED"] = "true"
      begin
        cli = Jargon.cli("cli", json: %({
          "type": "object",
          "properties": {
            "count": {"type": "integer", "env": "TEST_JARGON_COUNT"},
            "enabled": {"type": "boolean", "env": "TEST_JARGON_ENABLED"}
          }
        }))

        result = cli.parse([] of String)
        result["count"].as_i64.should eq(42)
        result["enabled"].as_bool.should be_true
      ensure
        ENV.delete("TEST_JARGON_COUNT")
        ENV.delete("TEST_JARGON_ENABLED")
      end
    end

    it "ignores unset env vars" do
      cli = Jargon.cli("cli", json: %({
        "type": "object",
        "properties": {
          "missing": {"type": "string", "env": "TEST_JARGON_NONEXISTENT_VAR"}
        }
      }))

      result = cli.parse([] of String)
      result["missing"]?.should be_nil
    end
  end

  describe "schema flatten" do
    it "resolves $ref from $defs" do
      schema = %({
        "type": "object",
        "$defs": {
          "name": {"type": "string", "minLength": 1}
        },
        "properties": {
          "user": {"$ref": "#/$defs/name"}
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["$defs"]?.should be_nil
      parsed["properties"]["user"]["type"].as_s.should eq("string")
      parsed["properties"]["user"]["minLength"].as_i.should eq(1)
    end

    it "resolves $ref from definitions" do
      schema = %({
        "type": "object",
        "definitions": {
          "count": {"type": "integer", "minimum": 0}
        },
        "properties": {
          "total": {"$ref": "#/definitions/count"}
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["definitions"]?.should be_nil
      parsed["properties"]["total"]["type"].as_s.should eq("integer")
      parsed["properties"]["total"]["minimum"].as_i.should eq(0)
    end

    it "resolves nested $refs" do
      schema = %({
        "type": "object",
        "$defs": {
          "address": {
            "type": "object",
            "properties": {
              "city": {"$ref": "#/$defs/city"}
            }
          },
          "city": {"type": "string"}
        },
        "properties": {
          "home": {"$ref": "#/$defs/address"}
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["$defs"]?.should be_nil
      parsed["properties"]["home"]["properties"]["city"]["type"].as_s.should eq("string")
    end

    it "resolves $refs in allOf" do
      schema = %({
        "type": "object",
        "$defs": {
          "base": {"properties": {"id": {"type": "string"}}}
        },
        "allOf": [
          {"$ref": "#/$defs/base"},
          {"properties": {"name": {"type": "string"}}}
        ]
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["$defs"]?.should be_nil
      parsed["allOf"][0]["properties"]["id"]["type"].as_s.should eq("string")
      parsed["allOf"][1]["properties"]["name"]["type"].as_s.should eq("string")
    end

    it "resolves $refs in array items" do
      schema = %({
        "type": "object",
        "$defs": {
          "tag": {"type": "string", "minLength": 1}
        },
        "properties": {
          "tags": {
            "type": "array",
            "items": {"$ref": "#/$defs/tag"}
          }
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["$defs"]?.should be_nil
      parsed["properties"]["tags"]["items"]["type"].as_s.should eq("string")
    end

    it "keeps unresolvable $refs unchanged" do
      schema = %({
        "type": "object",
        "properties": {
          "external": {"$ref": "https://example.com/schema.json"}
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["properties"]["external"]["$ref"].as_s.should eq("https://example.com/schema.json")
    end

    it "preserves Jargon extensions in flattened output" do
      schema = %({
        "type": "object",
        "$defs": {
          "verbose": {"type": "boolean", "short": "v", "description": "Verbose output"}
        },
        "properties": {
          "verbose": {"$ref": "#/$defs/verbose"}
        }
      })

      flattened = Jargon.flatten(schema)
      parsed = JSON.parse(flattened)

      parsed["properties"]["verbose"]["short"].as_s.should eq("v")
      parsed["properties"]["verbose"]["description"].as_s.should eq("Verbose output")
    end

    it "raises ArgumentError for a recursive $ref instead of recursing forever" do
      schema = %({
        "$defs": {"Node": {"type": "object", "properties": {"child": {"$ref": "#/$defs/Node"}}}},
        "properties": {"root": {"$ref": "#/$defs/Node"}}
      })

      expect_raises(ArgumentError, "Cannot flatten recursive $ref '#/$defs/Node'") do
        Jargon.flatten(schema)
      end
    end

    it "still flattens one definition used by several properties" do
      schema = %({
        "$defs": {"Port": {"type": "integer"}},
        "properties": {"a": {"$ref": "#/$defs/Port"}, "b": {"$ref": "#/$defs/Port"}}
      })

      parsed = JSON.parse(Jargon.flatten(schema))
      parsed["properties"]["a"]["type"].as_s.should eq("integer")
      parsed["properties"]["b"]["type"].as_s.should eq("integer")
    end
  end
end
