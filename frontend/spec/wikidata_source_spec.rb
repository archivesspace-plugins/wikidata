require_relative 'spec_helper'

# Imported records are attributed to Wikidata via the 'wikidata' name_source
# enum value (seeded by migrations/001_add_wikidata_name_source.rb), rather than
# the generic 'local' source.
class WikidataSourceTest < Minitest::Test

  def agent(data, qid = 'Q1')
    WikidataToAgent.new(data, qid).to_agent_hash
  end

  def primary_identifier(h)
    (h[:agent_record_identifiers] || []).find { |id| id[:primary_identifier] }
  end

  def test_person_primary_identifier_source_is_wikidata
    h = agent('label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'])
    assert_equal 'wikidata', primary_identifier(h)[:source]
  end

  def test_person_primary_name_source_is_wikidata
    h = agent('label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'])
    assert_equal 'wikidata', h[:names].first[:source]
  end

  def test_person_alias_source_is_wikidata
    h = agent('label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'], 'alias' => ['JD'])
    aliases = h[:names][1..]
    refute_empty aliases
    aliases.each { |n| assert_equal 'wikidata', n[:source] }
  end

  def test_corporate_name_source_is_wikidata
    h = agent({ 'label' => ['Acme Corp'], 'isCollectiveAgent' => ['true'] }, 'Q2')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    assert_equal 'wikidata', h[:names].first[:source]
    assert_equal 'wikidata', primary_identifier(h)[:source]
  end

  def test_family_name_source_is_wikidata
    h = agent({ 'label' => ['Doe family'], 'isFamily' => ['true'] }, 'Q3')
    assert_equal 'agent_family', h[:jsonmodel_type]
    assert_equal 'wikidata', h[:names].first[:source]
    assert_equal 'wikidata', primary_identifier(h)[:source]
  end

  # Secondary identifiers keep their dedicated sources (NAF / SNAC), only the
  # primary Wikidata identifier carries the wikidata source.
  def test_naf_identifier_keeps_naf_source
    h = agent('label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'],
              'libraryOfCongressAuthorityId' => ['n12345'])
    naf = (h[:agent_record_identifiers] || []).find { |id| id[:source] == 'naf' }
    refute_nil naf
    assert_equal 'n12345', naf[:record_identifier]
  end

  # VIAF cluster IDs (P214) are attributed to the dedicated 'viaf' source
  # (seeded by migrations/002_add_viaf_name_source.rb), not the generic 'local'.
  def test_viaf_identifier_source_is_viaf
    h = agent('label' => ['Grace Lee Boggs'], 'familyName' => ['Boggs'],
              'givenName' => ['Grace'], 'isHuman' => ['true'],
              'viafClusterId' => ['67976526'])
    viaf = (h[:agent_record_identifiers] || []).find { |id| id[:source] == 'viaf' }
    refute_nil viaf, 'VIAF identifier should use the viaf source'
    assert_equal '67976526', viaf[:record_identifier]
    refute viaf[:primary_identifier], 'VIAF id is a secondary identifier'
    # The VIAF id must not be mislabelled as a local identifier.
    locals = (h[:agent_record_identifiers] || []).select { |id| id[:source] == 'local' }
    assert locals.none? { |id| id[:record_identifier] == '67976526' }, 'VIAF id must not be a local identifier'
  end

  def test_wikidata_migration_file_is_valid_ruby
    path = File.expand_path('../../../migrations/001_add_wikidata_name_source.rb', __FILE__)
    assert File.exist?(path), 'Migration file should exist'
    # Parses without raising (Ruby 2.6 compatible syntax check).
    assert RubyVM::InstructionSequence.compile(File.read(path))
  end

  def test_viaf_migration_file_is_valid_ruby_and_adds_viaf
    path = File.expand_path('../../../migrations/002_add_viaf_name_source.rb', __FILE__)
    assert File.exist?(path), 'VIAF migration file should exist'
    src = File.read(path)
    assert RubyVM::InstructionSequence.compile(src)
    assert_match(/value\s*=\s*"viaf"/, src, 'Migration seeds the viaf value')
    assert_match(/name_source/, src, 'Migration targets the name_source enumeration')
  end
end
