require 'minitest/autorun'
require 'json'

# Load plugin models without requiring the full ArchivesSpace stack.
# Models that depend on ASpace libs (ashttp, asutils) are stubbed here.
MODELS_DIR = File.expand_path('../../models', __FILE__)
FIXTURES_DIR = File.expand_path('../fixtures', __FILE__)

# Create stub files for ASpace-specific gems so `require` succeeds outside ASpace.
STUBS_DIR = File.join(File.dirname(__FILE__), 'stubs')
Dir.mkdir(STUBS_DIR) unless File.directory?(STUBS_DIR)

# Stub ashttp
ashttp_stub = File.join(STUBS_DIR, 'ashttp.rb')
unless File.exist?(ashttp_stub)
  File.write(ashttp_stub, <<~RUBY)
    module ASHTTP
      def self.start_uri(*args, &block)
        raise "ASHTTP.start_uri should not be called in unit tests"
      end
    end
  RUBY
end

# Stub asutils
asutils_stub = File.join(STUBS_DIR, 'asutils.rb')
unless File.exist?(asutils_stub)
  File.write(asutils_stub, <<~RUBY)
    require 'tempfile'
    module ASUtils
      def self.tempfile(prefix)
        Tempfile.new(prefix)
      end
    end
  RUBY
end

$LOAD_PATH.unshift(STUBS_DIR)

# Load models in dependency order
require File.join(MODELS_DIR, 'wikidata_sparql_query')
require File.join(MODELS_DIR, 'wikidata_result_set')
require File.join(MODELS_DIR, 'wikidata_to_agent')

def require_searcher
  require File.join(MODELS_DIR, 'wikidata_searcher')
end

# Helper: load a JSON fixture file and return parsed hash
def load_fixture(name)
  path = File.join(FIXTURES_DIR, name)
  JSON.parse(File.read(path))
end

# Helper: load a fixture as raw JSON string
def load_fixture_raw(name)
  File.read(File.join(FIXTURES_DIR, name))
end
