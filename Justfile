# Jargon - Define your CLI jargon with JSON Schema

# Default task
default: check

# Install dependencies
install:
  shards install

# Update dependencies
update:
  shards update

# Check syntax (fast, no codegen)
check:
  crystal build --no-codegen src/jargon.cr

# Build the binary
build:
  crystal build src/jargon.cr -o bin/jargon

# Build release binary
release:
  crystal build --release src/jargon.cr -o bin/jargon

# Run the REPL
run:
  crystal run src/jargon.cr

# Run all tests
test:
  crystal spec

# Run specific test file
test-file FILE:
  crystal spec {{FILE}}

# Run tests with verbose output
test-verbose:
  crystal spec --verbose

# Record the conformance cases other implementations (jargon.rs) test against
conformance:
  rm -f conformance/*.json
  JARGON_RECORD=conformance crystal spec

# Generate API documentation
doc: doc-api

doc-api:
  rm -rf docs && crystal docs -o docs

# Open docs in browser
doc-open: doc
  xdg-open docs/index.html 2>/dev/null || open docs/index.html

# Format code
fmt:
  crystal tool format src spec

# Format check (no changes)
fmt-check:
  crystal tool format --check src spec

# Build the ameba linter (shards no longer compiles it on install)
ameba:
  mkdir -p bin && crystal build --release -o bin/ameba lib/ameba/bin/ameba.cr

# Run the linter
lint:
  bin/ameba

# Clean build artifacts
clean:
  rm -rf docs lib .crystal .shards bin/jargon

# Full rebuild
rebuild: clean install check

# Watch for changes and run check (requires entr)
watch:
  find src -name '*.cr' | entr -c just check

# Watch and run tests (requires entr)
watch-test:
  find src spec -name '*.cr' | entr -c just test

# Show lines of code
loc:
  @find src -name '*.cr' | xargs wc -l | tail -1

# List all tasks
list:
  @just --list
