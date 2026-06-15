require_relative 'spec_helper'

# Verifies external document mapping: a Wikidata link is always added, and when a
# Wikipedia sitelink is present it is added as a second external document.
class ExternalDocumentsTest < Minitest::Test

  def external_docs_for(data, qid)
    WikidataToAgent.new(data, qid).to_agent_hash[:external_documents] || []
  end

  def test_always_includes_wikidata_document
    docs = external_docs_for({ 'label' => ['Jane Doe'], 'isHuman' => ['true'] }, 'Q12345')
    wikidata = docs.find { |d| d[:title] == 'Wikidata' }
    refute_nil wikidata, 'Wikidata external document should always be present'
    assert_equal 'https://www.wikidata.org/wiki/Q12345', wikidata[:location]
  end

  def test_adds_wikipedia_document_when_sitelink_present
    data = {
      'label'        => ['Sara Gilfert'],
      'familyName'   => ['Gilfert'],
      'givenName'    => ['Sara'],
      'isHuman'      => ['true'],
      'wikipediaUrl' => ['https://en.wikipedia.org/wiki/Sara_Gilfert']
    }
    docs = external_docs_for(data, 'Q134990179')

    wikidata = docs.find { |d| d[:title] == 'Wikidata' }
    wikipedia = docs.find { |d| d[:title] == 'Wikipedia' }

    refute_nil wikidata, 'Wikidata document should be present'
    refute_nil wikipedia, 'Wikipedia document should be present when sitelink exists'
    assert_equal 'https://en.wikipedia.org/wiki/Sara_Gilfert', wikipedia[:location]
    assert_equal 2, docs.length, 'Should produce exactly Wikidata + Wikipedia documents'
  end

  def test_no_wikipedia_document_when_sitelink_absent
    docs = external_docs_for({ 'label' => ['Jane Doe'], 'isHuman' => ['true'] }, 'Q12345')
    assert_nil docs.find { |d| d[:title] == 'Wikipedia' }, 'No Wikipedia document without a sitelink'
    assert_equal 1, docs.length
  end

  def test_blank_wikipedia_url_is_ignored
    data = { 'label' => ['Jane Doe'], 'isHuman' => ['true'], 'wikipediaUrl' => ['   '] }
    docs = external_docs_for(data, 'Q12345')
    assert_nil docs.find { |d| d[:title] == 'Wikipedia' }, 'Blank Wikipedia URL should be ignored'
  end
end
