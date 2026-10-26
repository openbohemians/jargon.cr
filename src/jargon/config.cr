require "./yaml_reader"

module Jargon
  # Control whether config parse warnings are emitted to STDERR
  class_property? config_warnings : Bool = true

  class CLI
    # The config formats read without `config_format`, in the order they're
    # looked for.
    private BUILT_IN_CONFIG_FORMATS = ["yaml", "yml", "json"]

    @config_formats = {} of String => Proc(String, JSON::Any)

    # Load config from standard locations.
    # Supports YAML (.yaml, .yml) and JSON (.json) files, and any format
    # added with `config_format`, which is looked for ahead of them.
    #
    # Paths searched (in order):
    # 1. ./.config/{program_name}.yaml/.yml/.json (project local, flat; project: true only)
    # 2. ./.config/{program_name}/config.yaml/.yml/.json (project local, directory; project: true only)
    # 3. $XDG_CONFIG_HOME/{program_name}.yaml/.yml/.json (user global, flat)
    # 4. $XDG_CONFIG_HOME/{program_name}/config.yaml/.yml/.json (user global, directory)
    #
    # Project-local configs are read from the current directory, which may be
    # one someone else controls (a freshly cloned repository), and they would
    # take precedence over the user's own config. So they are off by default;
    # pass project: true to opt in.
    #
    # With merge: true (default), merges all configs found (project wins over user).
    # With merge: false, returns first config found.
    # Returns nil if no config file found.
    def load_config(*, merge : Bool = true, project : Bool = false) : JSON::Any?
      if merge
        load_config_merged(project)
      else
        load_config_first(project)
      end
    end

    # Returns the list of config paths `load_config` would search, given the
    # same `project:` setting.
    def config_paths(*, project : Bool = false) : Array(String)
      # Per the XDG spec, an unset, empty, or relative XDG_CONFIG_HOME is ignored.
      xdg_config = ENV["XDG_CONFIG_HOME"]?
      xdg_config = Path.home.join(".config").to_s unless xdg_config && Path[xdg_config].absolute?
      bases = [
        "#{xdg_config}/#{@program_name}",
        "#{xdg_config}/#{@program_name}/config",
      ]
      bases = ["./.config/#{@program_name}", "./.config/#{@program_name}/config"] + bases if project
      # For each base, check the added formats, then .yaml, .yml, .json
      extensions = @config_formats.keys.reject { |ext| BUILT_IN_CONFIG_FORMATS.includes?(ext) } + BUILT_IN_CONFIG_FORMATS
      bases.flat_map { |base| extensions.map { |ext| "#{base}.#{ext}" } }
    end

    # Read config files ending in `.ext` with the block, which turns a file's
    # text into anything that can be written as JSON: a TOML library's
    # `TOML.parse`, say. An added format is looked for ahead of YAML and
    # JSON, and ahead of formats added after it, so where a directory has
    # both `app.toml` and `app.yaml`, `app.toml` takes precedence. Adding
    # `yaml`, `yml`, or `json` replaces that extension's parser, and it keeps
    # its place.
    #
    # ```
    # cli.config_format("toml") { |text| TOML.parse(text) }
    # ```
    def config_format(ext : String, &block : String -> T) : self forall T
      if ext.empty? || ext.includes?('.') || ext.includes?('/') || ext.includes?('\\')
        raise ArgumentError.new("a config format's extension is the extension alone, such as \"toml\"; got #{ext.inspect}")
      end
      @config_formats[ext] = ->(text : String) do
        value = block.call(text)
        value.is_a?(JSON::Any) ? value : JSON.parse(value.to_json)
      end
      self
    end

    private def load_config_first(project : Bool) : JSON::Any?
      config_paths(project: project).each do |path|
        if File.exists?(path)
          return parse_config_file(path)
        end
      end
      nil
    end

    private def load_config_merged(project : Bool) : JSON::Any?
      # Load in reverse order (user first, project last) so project wins
      merged = {} of String => JSON::Any
      config_paths(project: project).reverse.each do |path|
        if File.exists?(path)
          if data = parse_config_file(path).try(&.as_h?)
            deep_merge!(merged, data)
          end
        end
      end
      merged.empty? ? nil : JSON::Any.new(merged)
    end

    # Deep merge source into target, recursively merging nested objects
    private def deep_merge!(target : Hash(String, JSON::Any), source : Hash(String, JSON::Any))
      source.each do |key, source_value|
        if target_value = target[key]?
          # Both have this key - check if both are objects for deep merge
          if (target_hash = target_value.as_h?) && (source_hash = source_value.as_h?)
            deep_merge!(target_hash, source_hash)
          else
            # Source wins for non-object values or mismatched types
            target[key] = source_value
          end
        else
          # Key only in source
          target[key] = source_value
        end
      end
    end

    private def parse_config_file(path : String) : JSON::Any?
      content = File.read(path)
      ext = File.extname(path).lchop('.')
      config = if parser = @config_formats[ext]?
                 parser.call(content)
               else
                 case ext
                 when "yaml", "yml"
                   JSON.parse(YAMLReader.parse(content).to_json)
                 when "json"
                   JSON.parse(content)
                 end
               end
      # An empty file configures nothing; anything else must be a mapping of
      # option defaults.
      return if config.nil? || config.raw.nil?
      raise ArgumentError.new("expected a mapping of option defaults at the top level") unless config.as_h?
      config
    rescue ex
      if Jargon.config_warnings?
        STDERR.puts "Warning: Failed to parse config file '#{path}': #{ex.message}"
      end
      nil
    end
  end
end
