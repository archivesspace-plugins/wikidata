require_relative 'spec_helper'

# WikidataSearcher depends on ashttp/nokogiri at load time.
# We only test the class methods and static logic here.
# Network-dependent methods (fetch_entity, search, results_to_marcxml_file)
# are tested via integration tests with mocked HTTP.

class WikidataSearcherExtractQidTest < Minitest::Test

  def setup
    require_searcher
  end

  # --- extract_qid ---

  def test_extracts_qid_from_full_url
    assert_equal 'Q42', WikidataSearcher.extract_qid('https://www.wikidata.org/wiki/Q42')
  end

  def test_extracts_qid_from_url_case_insensitive
    assert_equal 'Q42', WikidataSearcher.extract_qid('https://www.wikidata.org/wiki/q42')
  end

  def test_extracts_qid_from_prefixed_id
    assert_equal 'Q42', WikidataSearcher.extract_qid('Q42')
  end

  def test_extracts_qid_from_lowercase_prefixed_id
    assert_equal 'Q42', WikidataSearcher.extract_qid('q42')
  end

  def test_extracts_qid_from_bare_number
    assert_equal 'Q42', WikidataSearcher.extract_qid('42')
  end

  def test_extracts_qid_with_whitespace
    assert_equal 'Q42', WikidataSearcher.extract_qid('  Q42  ')
  end

  def test_returns_nil_for_nil_input
    assert_nil WikidataSearcher.extract_qid(nil)
  end

  def test_returns_nil_for_empty_string
    assert_nil WikidataSearcher.extract_qid('')
  end

  def test_returns_nil_for_blank_string
    assert_nil WikidataSearcher.extract_qid('   ')
  end

  def test_extracts_qid_from_entity_url
    assert_equal 'Q1299', WikidataSearcher.extract_qid('https://www.wikidata.org/wiki/Q1299')
  end

  def test_extracts_large_qid
    assert_equal 'Q117085185', WikidataSearcher.extract_qid('Q117085185')
  end
end
