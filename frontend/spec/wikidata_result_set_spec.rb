require_relative 'spec_helper'

class WikidataResultSetTest < Minitest::Test

  # --- Parsing ---

  def test_parses_sparql_bindings_into_data_hash
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    assert rs.valid?
    assert_equal ['Douglas'], rs.data['givenName']
    assert_equal ['Adams'], rs.data['familyName']
    assert_equal ['Q42'], rs.data['qNumber']
  end

  def test_handles_multiple_values_for_same_property
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    aliases = rs.data['alias']
    assert_kind_of Array, aliases
    assert_equal 3, aliases.length
    assert_includes aliases, 'Douglas Noel Adams'
    assert_includes aliases, 'Douglas N. Adams'
    assert_includes aliases, 'DNA'
  end

  def test_handles_nil_response
    rs = WikidataResultSet.new(nil, 'Q1')
    refute rs.valid?
    assert_empty rs.data
  end

  def test_handles_empty_string_response
    rs = WikidataResultSet.new('', 'Q1')
    refute rs.valid?
  end

  def test_handles_malformed_json
    rs = WikidataResultSet.new('not json at all', 'Q1')
    refute rs.valid?
    assert_match(/parse/i, rs.error)
  end

  def test_handles_empty_bindings
    json = '{"results": {"bindings": []}}'
    rs = WikidataResultSet.new(json, 'Q1')
    refute rs.valid?
  end

  # --- Agent Type Detection ---

  def test_person_agent_type
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    assert_equal 'agent_person', rs.agent_type
    assert rs.agent_type_valid?
  end

  def test_corporate_agent_type
    rs = WikidataResultSet.new(load_fixture_raw('q1299.json'), 'Q1299')
    assert_equal 'agent_corporate_entity', rs.agent_type
    assert rs.agent_type_valid?
  end

  def test_family_agent_type
    rs = WikidataResultSet.new(load_fixture_raw('q21026250.json'), 'Q21026250')
    assert_equal 'agent_family', rs.agent_type
    assert rs.agent_type_valid?
  end

  def test_invalid_entity_returns_nil_agent_type
    rs = WikidataResultSet.new(load_fixture_raw('q_invalid_entity.json'), 'Q5891')
    assert_nil rs.agent_type
    refute rs.agent_type_valid?
  end

  # --- Label and Description ---

  def test_label_returns_english_label
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    assert_equal 'Douglas Adams', rs.label
  end

  def test_description_returns_english_description
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    assert_match(/science fiction/, rs.description)
  end

  def test_label_falls_back_to_qid
    json = '{"results": {"bindings": [{"propertyName": {"value": "isHuman"}, "value": {"value": "true"}}]}}'
    rs = WikidataResultSet.new(json, 'Q999')
    assert_equal 'Q999', rs.label
  end

  # --- QID Normalization ---

  def test_normalizes_qid_uppercase
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'q42')
    assert_equal 'Q42', rs.qid
  end

  def test_adds_q_prefix_if_missing
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), '42')
    assert_equal 'Q42', rs.qid
  end

  # --- Preview Hash ---

  def test_preview_hash_structure
    rs = WikidataResultSet.new(load_fixture_raw('q42.json'), 'Q42')
    preview = rs.to_preview_hash
    assert_equal 'Q42', preview[:qid]
    assert_equal 'Douglas Adams', preview[:title]
    assert_equal 'Person', preview[:agent_type]
    assert preview[:agent_type_valid]
  end

  def test_corporate_preview_hash
    rs = WikidataResultSet.new(load_fixture_raw('q1299.json'), 'Q1299')
    preview = rs.to_preview_hash
    assert_equal 'Corporate', preview[:agent_type]
  end

  def test_family_preview_hash
    rs = WikidataResultSet.new(load_fixture_raw('q21026250.json'), 'Q21026250')
    preview = rs.to_preview_hash
    assert_equal 'Family', preview[:agent_type]
  end
end
