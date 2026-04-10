require_relative 'spec_helper'

class WikidataToMarcxmlTest < Minitest::Test

  # Helper: build a WikidataToMarcxml from a fixture
  def converter_from_fixture(fixture_name, qid)
    rs = WikidataResultSet.new(load_fixture_raw(fixture_name), qid)
    WikidataToMarcxml.new(rs.data, qid)
  end

  def marcxml_from_fixture(fixture_name, qid)
    converter = converter_from_fixture(fixture_name, qid)
    parse_marcxml(converter.to_marcxml)
  end

  # =========================================================
  # Person (Q42 - Douglas Adams) - Crosswalk validation
  # =========================================================

  def test_person_agent_type
    c = converter_from_fixture('q42.json', 'Q42')
    assert_equal 'agent_person', c.agent_type
  end

  # --- Leader ---

  def test_person_leader
    doc = marcxml_from_fixture('q42.json', 'Q42')
    leader = REXML::XPath.first(doc, '//leader')
    assert leader
    assert_match(/nz/, leader.text, 'Leader should indicate authority record')
  end

  # --- Control Field 001 ---

  def test_person_controlfield_001
    doc = marcxml_from_fixture('q42.json', 'Q42')
    cf = REXML::XPath.first(doc, "//controlfield[@tag='001']")
    assert cf
    assert_equal 'Q42', cf.text
  end

  # --- Record Identifiers (MARC 024) ---
  # Crosswalk: Q42/wikidata(primary), n80076765/LCN, w65h7md1/SNAC, 113230702/viaf

  def test_person_wikidata_identifier
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields = find_datafields(doc, '024')
    wd = fields.find { |f| subfield_value(f, '2') == 'wikidata' }
    assert wd, 'Must have wikidata 024 field'
    assert_equal 'Q42', subfield_value(wd, 'a')
    assert_equal '7', wd.attribute('ind1').value
  end

  def test_person_lcn_identifier
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields = find_datafields(doc, '024')
    lcn = fields.find { |f| subfield_value(f, '2') == 'Library of Congress Name Authority File' }
    assert lcn, 'Must have LCN 024 field'
    assert_equal 'n80076765', subfield_value(lcn, 'a')
  end

  def test_person_snac_identifier
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields = find_datafields(doc, '024')
    snac = fields.find { |f| subfield_value(f, '2') == 'SNAC' }
    assert snac, 'Must have SNAC 024 field'
    assert_equal 'w65h7md1', subfield_value(snac, 'a')
  end

  def test_person_viaf_identifier
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields = find_datafields(doc, '024')
    viaf = fields.find { |f| subfield_value(f, '2') == 'viaf' }
    assert viaf, 'Must have VIAF 024 field'
    assert_equal '113230702', subfield_value(viaf, 'a')
  end

  def test_person_has_four_identifiers
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields = find_datafields(doc, '024')
    assert_equal 4, fields.length, 'Person with all IDs should have 4 MARC 024 fields'
  end

  # --- Person Name (MARC 100) ---
  # Crosswalk: familyName → Primary Part of Name, givenName → Rest of Name, name_order=Indirect

  def test_person_name_inverted_order
    doc = marcxml_from_fixture('q42.json', 'Q42')
    field = find_datafields(doc, '100').first
    assert field, 'Must have MARC 100 field'
    assert_equal '1', field.attribute('ind1').value, 'ind1=1 for inverted (indirect) order'
  end

  def test_person_name_value
    doc = marcxml_from_fixture('q42.json', 'Q42')
    field = find_datafields(doc, '100').first
    name = subfield_value(field, 'a')
    # "Adams, Douglas" - MARC importer splits on comma: primary_name=Adams, rest_of_name=Douglas
    assert_equal 'Adams, Douglas', name
  end

  # --- Person Name with label-only fallback (no given/family) ---
  # Crosswalk: pull whole name in Primary Part of Name, select "Direct" name order

  def test_person_label_only_uses_direct_order
    doc = marcxml_from_fixture('q_no_name_parts.json', 'Q99999')
    field = find_datafields(doc, '100').first
    assert field
    assert_equal '0', field.attribute('ind1').value, 'ind1=0 for direct order when no given/family'
  end

  def test_person_label_only_uses_full_label
    doc = marcxml_from_fixture('q_no_name_parts.json', 'Q99999')
    field = find_datafields(doc, '100').first
    assert_equal 'John Smith', subfield_value(field, 'a')
  end

  # --- Person Aliases (MARC 400) ---
  # Crosswalk: each English alias as separate name form, Direct order, not authorized

  def test_person_aliases_as_marc_400
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields_400 = find_datafields(doc, '400')
    assert fields_400.length >= 3, "Expected at least 3 alias 400 fields, got #{fields_400.length}"
    alias_names = fields_400.map { |f| subfield_value(f, 'a') }
    assert_includes alias_names, 'Douglas Noel Adams'
    assert_includes alias_names, 'Douglas N. Adams'
    assert_includes alias_names, 'DNA'
  end

  def test_person_aliases_use_direct_order
    doc = marcxml_from_fixture('q42.json', 'Q42')
    fields_400 = find_datafields(doc, '400')
    fields_400.each do |f|
      assert_equal '0', f.attribute('ind1').value,
        "Alias '#{subfield_value(f, 'a')}' should use ind1=0 (direct order)"
    end
  end

  # --- Person Dates (MARC 046) ---
  # Crosswalk: dateOfBirth → begin (1952-03-11), dateOfDeath → end (2001-05-11)
  # Both present → range type

  def test_person_dates_begin
    doc = marcxml_from_fixture('q42.json', 'Q42')
    field = find_datafields(doc, '046').first
    assert field, 'Must have MARC 046 field'
    assert_equal '19520311', subfield_value(field, 'f'), 'Begin date should be 19520311'
  end

  def test_person_dates_end
    doc = marcxml_from_fixture('q42.json', 'Q42')
    field = find_datafields(doc, '046').first
    assert_equal '20010511', subfield_value(field, 'g'), 'End date should be 20010511'
  end

  # --- Person Biography Note (MARC 678) ---
  # Crosswalk: description → Biographical Note

  def test_person_bioghist_note
    doc = marcxml_from_fixture('q42.json', 'Q42')
    field = find_datafields(doc, '678').first
    assert field, 'Must have MARC 678 field'
    assert_equal '0', field.attribute('ind1').value, 'ind1=0 for biographical note'
    assert_match(/science fiction/, subfield_value(field, 'a'))
  end

  # =========================================================
  # Corporate Entity (Q1299 - The Beatles) - Crosswalk validation
  # =========================================================

  def test_corporate_agent_type
    c = converter_from_fixture('q1299.json', 'Q1299')
    assert_equal 'agent_corporate_entity', c.agent_type
  end

  # --- Corporate Name (MARC 110) ---
  # Crosswalk: itemLabel → Primary Part of Name

  def test_corporate_name_tag
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    field = find_datafields(doc, '110').first
    assert field, 'Corporate entity must use MARC 110'
    assert_equal 'The Beatles', subfield_value(field, 'a')
  end

  def test_corporate_name_ind1
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    field = find_datafields(doc, '110').first
    assert_equal '2', field.attribute('ind1').value
  end

  # --- Corporate Aliases (MARC 410) ---

  def test_corporate_aliases_as_marc_410
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    fields_410 = find_datafields(doc, '410')
    assert fields_410.length >= 2, "Expected at least 2 corporate alias fields, got #{fields_410.length}"
    alias_names = fields_410.map { |f| subfield_value(f, 'a') }
    assert_includes alias_names, 'Beatles'
    assert_includes alias_names, 'Fab Four'
  end

  # --- Corporate Dates (MARC 046) ---
  # Crosswalk: inception (1960, year-only) → begin, dissolvedDate (1970-04-10) → end
  # Both present → range

  def test_corporate_dates_begin_year_only
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    field = find_datafields(doc, '046').first
    assert field, 'Must have MARC 046 field'
    begin_date = subfield_value(field, 'f')
    # Year-only date (+1960-00-00T00:00:00Z) should produce "1960" not "19600101"
    assert_equal '1960', begin_date, 'Year-only date should be just the year'
  end

  def test_corporate_dates_end_full
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    field = find_datafields(doc, '046').first
    assert_equal '19700410', subfield_value(field, 'g'), 'End date should be 19700410'
  end

  # --- Corporate Identifiers ---

  def test_corporate_has_identifiers
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    fields = find_datafields(doc, '024')
    sources = fields.map { |f| subfield_value(f, '2') }
    assert_includes sources, 'wikidata'
    assert_includes sources, 'Library of Congress Name Authority File'
    assert_includes sources, 'SNAC'
    assert_includes sources, 'viaf'
  end

  # --- Corporate Biography Note ---

  def test_corporate_bioghist_note
    doc = marcxml_from_fixture('q1299.json', 'Q1299')
    field = find_datafields(doc, '678').first
    assert field
    assert_match(/pop rock band/, subfield_value(field, 'a'))
  end

  # =========================================================
  # Family (Q21026250 - Clinton family) - Crosswalk validation
  # =========================================================

  def test_family_agent_type
    c = converter_from_fixture('q21026250.json', 'Q21026250')
    assert_equal 'agent_family', c.agent_type
  end

  # --- Family Name (MARC 100 ind1=3) ---
  # Crosswalk: itemLabel → Family Name

  def test_family_name_tag_and_indicator
    doc = marcxml_from_fixture('q21026250.json', 'Q21026250')
    field = find_datafields(doc, '100').first
    assert field, 'Family must use MARC 100'
    assert_equal '3', field.attribute('ind1').value, 'ind1=3 for family name'
    assert_equal 'Clinton family', subfield_value(field, 'a')
  end

  # --- Family with no dates ---

  def test_family_no_dates
    doc = marcxml_from_fixture('q21026250.json', 'Q21026250')
    fields = find_datafields(doc, '046')
    assert_empty fields, 'Family with no dates should have no 046 field'
  end

  # --- Family Identifiers ---

  def test_family_wikidata_identifier
    doc = marcxml_from_fixture('q21026250.json', 'Q21026250')
    fields = find_datafields(doc, '024')
    wd = fields.find { |f| subfield_value(f, '2') == 'wikidata' }
    assert wd
    assert_equal 'Q21026250', subfield_value(wd, 'a')
  end

  def test_family_skips_missing_identifiers
    doc = marcxml_from_fixture('q21026250.json', 'Q21026250')
    fields = find_datafields(doc, '024')
    # Clinton family has no LCN, SNAC, or VIAF
    assert_equal 1, fields.length, 'Should only have wikidata identifier'
  end

  # =========================================================
  # Date Edge Cases
  # =========================================================

  # Year-only precision: +1950-00-00T00:00:00Z → "1950" (not "19500101")

  def test_year_only_date_precision
    doc = marcxml_from_fixture('q117085185.json', 'Q117085185')
    field = find_datafields(doc, '046').first
    assert field
    begin_date = subfield_value(field, 'f')
    assert_equal '1950', begin_date, 'Year-only date should output year only'
  end

  # Birth only, no death → single date

  def test_single_date_birth_only
    doc = marcxml_from_fixture('q117085185.json', 'Q117085185')
    field = find_datafields(doc, '046').first
    assert field
    assert_nil subfield_value(field, 'g'), 'No end date when death is missing'
  end

  # Full date precision: +1980-06-15T00:00:00Z → "19800615"

  def test_full_date_precision
    doc = marcxml_from_fixture('q_no_name_parts.json', 'Q99999')
    field = find_datafields(doc, '046').first
    assert field
    assert_equal '19800615', subfield_value(field, 'f')
  end

  # =========================================================
  # Date Parsing Unit Tests
  # =========================================================

  def test_parse_full_date
    c = converter_from_fixture('q42.json', 'Q42')
    result = c.send(:parse_wikidata_date, '+1952-03-11T00:00:00Z')
    assert_equal '19520311', result
  end

  def test_parse_year_only_date
    c = converter_from_fixture('q42.json', 'Q42')
    result = c.send(:parse_wikidata_date, '+1960-00-00T00:00:00Z')
    assert_equal '1960', result, 'Year-only should not pad to YYYYMMDD'
  end

  def test_parse_year_month_date
    c = converter_from_fixture('q42.json', 'Q42')
    result = c.send(:parse_wikidata_date, '+1960-06-00T00:00:00Z')
    assert_equal '196006', result, 'Year-month should not pad day'
  end

  def test_parse_nil_date
    c = converter_from_fixture('q42.json', 'Q42')
    assert_nil c.send(:parse_wikidata_date, nil)
  end

  def test_parse_empty_date
    c = converter_from_fixture('q42.json', 'Q42')
    assert_nil c.send(:parse_wikidata_date, '')
  end

  def test_parse_plain_year
    c = converter_from_fixture('q42.json', 'Q42')
    result = c.send(:parse_wikidata_date, '1960')
    assert_equal '1960', result
  end

  # =========================================================
  # XML Well-formedness
  # =========================================================

  def test_generates_valid_xml
    %w[q42.json q1299.json q21026250.json q117085185.json q_no_name_parts.json].each do |fixture|
      qid = load_fixture(fixture)['results']['bindings'].find { |b|
        b.dig('propertyName', 'value') == 'qNumber'
      }&.dig('value', 'value') || 'Q1'
      c = converter_from_fixture(fixture, qid)
      xml = c.to_marcxml
      doc = REXML::Document.new(xml)
      assert doc.root, "#{fixture} should produce valid XML with a root element"
    end
  end

  def test_escapes_special_characters_in_description
    # Build data with special XML characters
    data = {
      'label' => ['Test & <Entity>'],
      'description' => ['A "quoted" & <special> description'],
      'isHuman' => ['true'],
      'qNumber' => ['Q999']
    }
    c = WikidataToMarcxml.new(data, 'Q999')
    xml = c.to_marcxml
    # Should not raise and should be parseable
    doc = REXML::Document.new(xml)
    assert doc.root
  end
end
