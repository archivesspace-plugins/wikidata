require 'minitest/autorun'
require 'json'
require 'rexml/document'
require 'cgi'

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
require File.join(MODELS_DIR, 'wikidata_to_marcxml')

# WikidataSearcher depends on nokogiri at load time.
def require_searcher
  begin
    require 'nokogiri'
  rescue LoadError
    # Skip nokogiri-dependent tests if not installed
  end
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

# Helper: parse MARCXML string and return REXML document
def parse_marcxml(xml_string)
  REXML::Document.new(xml_string)
end

# Helper: find all datafields with a given tag in a MARCXML document
def find_datafields(doc, tag)
  REXML::XPath.match(doc, "//datafield[@tag='#{tag}']")
end

# Helper: get subfield value from a datafield element
def subfield_value(datafield, code)
  sf = REXML::XPath.first(datafield, "subfield[@code='#{code}']")
  sf&.text
end
