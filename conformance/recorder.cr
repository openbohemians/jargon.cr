# Records the public Jargon calls the spec suite makes, with their inputs and
# results, as language-neutral conformance cases for other implementations
# (jargon.rs). It is compiled in only when JARGON_RECORD names the output
# directory:
#
#     JARGON_RECORD=conformance crystal spec
#
# Every case is what this implementation actually did, so the case files are
# regenerated, never edited by hand. A case's `cli` is the list of calls that
# rebuilt its CLI, replayable in order.
require "json"
require "yaml"

module Jargon
  module Conformance
    # One call that builds or configures a CLI. `nested` is a CLI attached
    # as a subcommand, serialized when the case is recorded (it may still be
    # configured after it is attached).
    record Op, fields : Hash(String, JSON::Any), nested : CLI? = nil

    # Tilde expansion depends on the home directory; cases record this one
    # instead of the machine's, and set HOME to it.
    HOME_STANDIN = "/home/jargon"

    @@cases = Hash(String, Array(JSON::Any)).new { |hash, kind| hash[kind] = [] of JSON::Any }
    @@seen = Set(String).new
    class_property? active = false
    class_property example = ""

    def self.any(value) : JSON::Any
      JSON.parse(value.to_json)
    end

    def self.op(**fields) : Op
      Op.new(any(fields).as_h)
    end

    # The op for a YAML source, which also carries its documents as JSON,
    # so an implementation without YAML (jargon.rs) can replay it. They
    # are null when the YAML doesn't parse.
    def self.yaml_op(**fields) : Op
      op = op(**fields)
      op.fields["documents"] = any(yaml_documents(op.fields["text"].as_s))
      op
    end

    # The op for a schema file, from its extension and content.
    def self.file_op(path : String, **fields) : Op
      fields = fields.merge(ext: File.extname(path), text: File.read(path))
      path.ends_with?(".yaml") || path.ends_with?(".yml") ? yaml_op(**fields) : op(**fields)
    end

    def self.yaml_documents(text : String) : Array(JSON::Any)?
      YAML.parse_all(text).map { |doc| JSON.parse(doc.to_json) }
    rescue YAML::ParseException
      nil
    end

    def self.recipe(ops : Array(Op)) : JSON::Any
      any(ops.map do |op|
        if nested = op.nested
          op.fields.merge({"cli" => recipe(nested.conformance_ops)})
        else
          op.fields
        end
      end)
    end

    # Record a case of `kind` (the case file it goes in); identical cases
    # are kept once. JSON can't carry invalid UTF-8, so a case containing it
    # is left out.
    def self.add(kind : String, fields : Hash(String, JSON::Any)) : Nil
      key = "#{kind}:#{fields.to_json}"
      return if @@seen.includes?(key) || !key.valid_encoding?
      @@seen << key
      @@cases[kind] << JSON::Any.new({"spec" => JSON::Any.new(example)}.merge(fields))
    end

    # Run a top-level call, recording `fields` plus its outcome under `kind`
    # (only when it raises, unless `successes`). Calls Jargon makes on itself
    # while one is running aren't cases.
    def self.call(kind : String, fields : Hash(String, JSON::Any), successes : Bool = true, &)
      return yield if active?
      self.active = true
      begin
        result = yield
        add(kind, fields.merge({"expect" => outcome(result)})) if successes
        result
      rescue ex
        add(kind, fields.merge({"expect" => any({raises: ex.message})}))
        raise ex
      ensure
        self.active = false
      end
    end

    def self.outcome(result) : JSON::Any
      case result
      when Result
        any({
          data:             rehome(result.data),
          errors:           result.errors,
          subcommand:       result.subcommand,
          help:             result.help_requested?,
          help_subcommand:  result.help_subcommand,
          completion_shell: result.completion_shell,
        })
      when CLI, Schema, Nil
        JSON::Any.new(nil)
      else
        any(result)
      end
    end

    # Replace the machine's home directory at the start of strings with
    # HOME_STANDIN.
    def self.rehome(value : JSON::Any) : JSON::Any
      home = Path.home.to_s
      case raw = value.raw
      when String
        raw.starts_with?(home) ? JSON::Any.new(HOME_STANDIN + raw[home.size..]) : value
      when Array
        JSON::Any.new(raw.map { |item| rehome(item) })
      when Hash
        JSON::Any.new(raw.transform_values { |item| rehome(item) })
      else
        value
      end
    end

    # The environment variables a CLI's schemas read, as currently set; HOME
    # is the stand-in when a schema has a `format: path` field.
    def self.environment(cli : CLI) : Hash(String, String)
      names = Set(String).new
      paths = collect_cli(cli, names)
      env = {} of String => String
      names.each do |name|
        if value = ENV[name]?
          env[name] = value
        end
      end
      env["HOME"] = HOME_STANDIN if paths
      env
    end

    private def self.collect_cli(cli : CLI, names : Set(String)) : Bool
      paths = false
      if schema = cli.schema
        paths |= collect_schema(schema, names)
      end
      cli.subcommands.each_value do |sub|
        paths |= sub.is_a?(CLI) ? collect_cli(sub, names) : collect_schema(sub, names)
      end
      paths
    end

    private def self.collect_schema(schema : Schema, names : Set(String)) : Bool
      paths = collect_property(schema.root, names)
      schema.definitions.each_value { |prop| paths |= collect_property(prop, names) }
      paths
    end

    private def self.collect_property(prop : Property, names : Set(String)) : Bool
      if env = prop.env
        names << env
      end
      paths = prop.format == "path"
      prop.properties.try &.each_value { |child| paths |= collect_property(child, names) }
      prop.items.try { |items| paths |= collect_property(items, names) }
      paths
    end

    def self.write(dir : String) : Nil
      Dir.mkdir_p(dir)
      @@cases.each do |kind, cases|
        File.write(File.join(dir, "#{kind}.json"), cases.to_pretty_json + "\n")
      end
    end
  end

  class Schema
    property conformance_source : String?

    def self.from_json(json_string : String) : Schema
      schema = Conformance.call("load", {"schema" => JSON::Any.new(json_string)}, successes: false) { previous_def }
      schema.conformance_source = json_string
      schema
    end

    def self.from_json_any(json : JSON::Any) : Schema
      schema = previous_def
      schema.conformance_source = json.to_json
      schema
    end
  end

  class CLI
    @conformance_ops : Array(Conformance::Op)?

    def conformance_ops : Array(Conformance::Op)
      @conformance_ops ||= if schema = @schema
                             [Conformance.op(op: "from_schema", program: @program_name, text: schema.conformance_source)]
                           else
                             [Conformance.op(op: "new", program: @program_name)]
                           end
    end

    def conformance_ops=(@conformance_ops : Array(Conformance::Op))
    end

    def conformance_recipe : JSON::Any
      Conformance.recipe(conformance_ops)
    end

    # ---- construction --------------------------------------------------

    def self.from_json(json : String, program_name : String = "cli") : CLI
      ops = [Conformance.op(op: "from_json", program: program_name, text: json)]
      cli = Conformance.call("load", {"cli" => Conformance.recipe(ops)}, successes: false) { previous_def }
      cli.conformance_ops = ops
      cli
    end

    def self.from_yaml(yaml : String, program_name : String = "cli") : CLI
      ops = [Conformance.yaml_op(op: "from_yaml", program: program_name, text: yaml)]
      cli = Conformance.call("load", {"cli" => Conformance.recipe(ops)}, successes: false) { previous_def }
      cli.conformance_ops = ops
      cli
    end

    def self.from_file(path : String, program_name : String = "cli") : CLI
      ops = [Conformance.file_op(path, op: "from_file", program: program_name)]
      cli = Conformance.call("load", {"cli" => Conformance.recipe(ops)}, successes: false) { previous_def }
      cli.conformance_ops = ops
      cli
    end

    def subcommand(name : String, schema : Schema)
      previous_def
      conformance_ops << Conformance.op(op: "subcommand_schema", name: name, text: schema.conformance_source)
    end

    def subcommand(name : String, cli : CLI)
      previous_def
      conformance_ops << Conformance::Op.new(Conformance.any({op: "subcommand_cli", name: name}).as_h, cli)
    end

    def subcommand(name : String, *, json : String)
      add_subcommand_op(Conformance.op(op: "subcommand_json", name: name, text: json)) { previous_def }
    end

    def subcommand(name : String, *, yaml : String)
      add_subcommand_op(Conformance.yaml_op(op: "subcommand_yaml", name: name, text: yaml)) { previous_def }
    end

    def subcommand(name : String, *, file : String)
      add_subcommand_op(Conformance.file_op(file, op: "subcommand_file", name: name)) { previous_def }
    end

    def subcommand(*, file : String)
      add_subcommand_op(Conformance.file_op(file, op: "subcommand_file", name: nil)) { previous_def }
    end

    private def add_subcommand_op(op : Conformance::Op, &) : Nil
      Conformance.call("load", {"cli" => Conformance.recipe(conformance_ops + [op])}, successes: false) { yield; nil }
      conformance_ops << op
    end

    def default_subcommand(name : String)
      previous_def
      conformance_ops << Conformance.op(op: "default_subcommand", name: name)
    end

    def subcommand_key(key : String)
      previous_def
      conformance_ops << Conformance.op(op: "subcommand_key", key: key)
    end

    def bare_assignment(enabled : Bool)
      previous_def
      conformance_ops << Conformance.op(op: "bare_assignment", value: enabled)
    end

    # ---- parsing and validation ----------------------------------------

    def parse(args : Array(String), input : IO, *, defaults : Defaults? = nil) : Result
      return previous_def if Conformance.active?

      fields = {"cli" => conformance_recipe, "args" => Conformance.any(args)}
      env = Conformance.environment(self)
      fields["env"] = Conformance.any(env) unless env.empty?
      if input.is_a?(IO::Memory)
        stdin = input.gets_to_end
        input.rewind
        fields["stdin"] = JSON::Any.new(stdin) unless stdin.empty?
      end
      fields["defaults"] = Conformance.any(defaults) if defaults
      Conformance.call("parse", fields) { previous_def }
    end

    def validate(data : Hash(String, JSON::Any), subcommand : String? = nil) : Array(String)
      fields = {"cli" => conformance_recipe, "data" => Conformance.any(data), "subcommand" => Conformance.any(subcommand)}
      Conformance.call("validate", fields) { previous_def }
    end

    # ---- help and completion -------------------------------------------

    def help : String
      Conformance.call("help", {"cli" => conformance_recipe, "subcommand" => JSON::Any.new(nil)}) { previous_def }
    end

    def help(subcommand : String) : String
      Conformance.call("help", {"cli" => conformance_recipe, "subcommand" => JSON::Any.new(subcommand)}) { previous_def }
    end

    def bash_completion(command : String = @program_name) : String
      Conformance.call("shim", {"cli" => conformance_recipe, "shell" => JSON::Any.new("bash"), "command" => JSON::Any.new(command)}) { previous_def }
    end

    def zsh_completion(command : String = @program_name) : String
      Conformance.call("shim", {"cli" => conformance_recipe, "shell" => JSON::Any.new("zsh"), "command" => JSON::Any.new(command)}) { previous_def }
    end

    def fish_completion(command : String = @program_name) : String
      Conformance.call("shim", {"cli" => conformance_recipe, "shell" => JSON::Any.new("fish"), "command" => JSON::Any.new(command)}) { previous_def }
    end
  end

  class Completion
    # Dynamic completers are code, so only schema-driven completion is
    # recorded.
    def candidates(words : Array(String), cword : Int32) : Array(String)
      return previous_def unless @cli.completers.empty?
      fields = {"cli" => @cli.conformance_recipe, "words" => Conformance.any(words), "cword" => JSON::Any.new(cword.to_i64)}
      Conformance.call("complete", fields) { previous_def }
    end
  end

  module Validator
    def self.validate(data : Hash(String, JSON::Any), schema : Schema) : Array(String)
      return previous_def unless source = schema.conformance_source
      fields = {"schema" => JSON::Any.new(source), "data" => Conformance.any(data)}
      Conformance.call("validate", fields) { previous_def }
    end
  end

  def self.merge(sub : String, global : String) : String
    Conformance.call("utility", {"merge" => Conformance.any([sub, global])}) { previous_def }
  end

  def self.flatten(schema : String) : String
    Conformance.call("utility", {"flatten" => JSON::Any.new(schema)}) { previous_def }
  end
end

Spec.around_each do |example|
  names = [example.example.description]
  group = example.example.parent
  while group.is_a?(Spec::ExampleGroup)
    names.unshift(group.description)
    group = group.parent
  end
  names.shift if names.size > 1 && names.first == "Jargon"
  Jargon::Conformance.example = names.join(" > ")
  example.run
end

Spec.after_suite { Jargon::Conformance.write(ENV["JARGON_RECORD"]) }
