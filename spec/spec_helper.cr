require "spec"
require "../src/jargon"

# `just conformance` records the cases other implementations test against.
{% if env("JARGON_RECORD") %}
  require "../conformance/recorder"
{% end %}
