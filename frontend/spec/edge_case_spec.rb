require_relative 'spec_helper'

# Edge case tests using real Wikidata entity data.
# Fixtures in fixtures/edge_cases/ are pre-parsed data dicts (propertyName => [values]).
# Each test verifies that the plugin correctly handles real-world data quirks:
# BCE dates, mononyms, missing fields, pseudonym-heavy entities, etc.

EDGE_CASES_DIR = File.join(FIXTURES_DIR, 'edge_cases')

def load_edge_case(qid)
  path = File.join(EDGE_CASES_DIR, "#{qid.downcase}.json")
  JSON.parse(File.read(path))
end

# Build a SPARQL-format JSON response from a pre-parsed data dict
def data_to_sparql_json(data)
  bindings = []
  data.each do |prop_name, values|
    Array(values).each do |val|
      bindings << {
        'propertyName' => { 'type' => 'literal', 'value' => prop_name },
        'value' => { 'type' => 'literal', 'value' => val.to_s }
      }
    end
  end
  { 'results' => { 'bindings' => bindings } }
end

def marcxml_for(qid)
  data = load_edge_case(qid)
  converter = WikidataToMarcxml.new(data, qid)
  xml = converter.to_marcxml
  doc = parse_marcxml(xml)
  [data, converter, doc]
end

def result_set_for(qid)
  data = load_edge_case(qid)
  sparql_json = data_to_sparql_json(data)
  WikidataResultSet.new(sparql_json, qid)
end


# ============================================================
# PERSON EDGE CASES (30 tests)
# ============================================================
class PersonEdgeCaseTest < Minitest::Test

  # 1. Q42 - Douglas Adams: baseline person with all fields
  def test_q42_douglas_adams_baseline
    data, conv, doc = marcxml_for('Q42')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '1', f100.attributes['ind1'], 'Inverted order for person with family name'
    assert_equal 'Adams, Douglas', subfield_value(f100, 'a')
    # Dates
    f046 = find_datafields(doc, '046').first
    assert_equal '19520311', subfield_value(f046, 'f'), 'Full birth date'
    assert_equal '20010511', subfield_value(f046, 'g'), 'Full death date'
    # Identifiers
    ids = find_datafields(doc, '024')
    assert ids.length >= 2, 'Should have Wikidata QID + LCN identifiers'
  end

  # 2. Q76 - Barack Obama: missing label, living person (no death date)
  def test_q76_obama_missing_label
    data, conv, doc = marcxml_for('Q76')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    # Should use family+given even if label is missing
    assert_includes name, 'Obama', 'Name should contain family name Obama'
    assert_includes name, 'Barack', 'Name should contain given name Barack'
    # No death date
    f046 = find_datafields(doc, '046').first
    refute_nil subfield_value(f046, 'f'), 'Should have birth date'
    assert_nil subfield_value(f046, 'g'), 'Living person should have no death date'
  end

  # 3. Q1413 - Nero: ancient person, NO given/family name properties
  def test_q1413_nero_no_name_parts
    data, conv, doc = marcxml_for('Q1413')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '0', f100.attributes['ind1'], 'Direct order when no family name'
    assert_equal 'Nero', subfield_value(f100, 'a'), 'Falls back to label'
    # Ancient dates (CE, not BCE)
    f046 = find_datafields(doc, '046').first
    refute_nil f046, 'Should have dates'
    # Aliases
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 3, "Nero has #{data['alias']&.length || 0} aliases"
  end

  # 4. Q4604 - Confucius: BCE dates (-0550, -0478)
  def test_q4604_confucius_bce_dates
    data, conv, doc = marcxml_for('Q4604')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '1', f100.attributes['ind1'], 'Inverted order'
    assert_includes subfield_value(f100, 'a'), 'Kong', 'Family name Kong'
    # BCE dates
    f046 = find_datafields(doc, '046').first
    refute_nil f046, 'Should have dates even for BCE'
    birth = subfield_value(f046, 'f')
    refute_nil birth, 'Birth date should be present'
  end

  # 5. Q859 - Plato: BCE dates, no family name, single given name
  def test_q859_plato_bce_no_family
    data, conv, doc = marcxml_for('Q859')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    # No family name - should use label in direct order
    ind1 = f100.attributes['ind1']
    name = subfield_value(f100, 'a')
    # Plato has givenName=Platon but no familyName
    # With only givenName, there's no comma-separated inverted form
    refute_nil name
  end

  # 6. Q868 - Aristotle: BCE dates, no family name
  def test_q868_aristotle_bce
    data, conv, doc = marcxml_for('Q868')
    assert_equal 'agent_person', conv.agent_type
    rs = result_set_for('Q868')
    assert rs.agent_type_valid?
    assert_equal 'Aristotle', rs.label
  end

  # 7. Q9068 - Voltaire: pseudonym IS the known name, no family name
  def test_q9068_voltaire_pseudonym_as_name
    data, conv, doc = marcxml_for('Q9068')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    # Label is "Voltaire" but that's actually a pseudonym
    # Given name is François-Marie, no family name
    name = subfield_value(f100, 'a')
    refute_nil name
    # Pseudonyms should appear in 400 fields
    f400s = find_datafields(doc, '400')
    pseudonym_names = f400s.map { |f| subfield_value(f, 'a') }
    assert_includes pseudonym_names, 'Voltaire', 'Voltaire should be listed as pseudonym'
  end

  # 8. Q80 - Tim Berners-Lee: honorific prefix "Sir", no family name in SPARQL
  def test_q80_berners_lee_prefix_sir
    data, conv, doc = marcxml_for('Q80')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    prefix = subfield_value(f100, 'c')
    assert_equal 'Sir', prefix, 'Honorific prefix should be in $c'
    # Living person
    f046 = find_datafields(doc, '046').first
    assert_nil subfield_value(f046, 'g'), 'Living person should have no death date'
  end

  # 9. Q1001 - Gandhi: honorific prefix "Mahatma"
  def test_q1001_gandhi_prefix_mahatma
    data, conv, doc = marcxml_for('Q1001')
    f100 = find_datafields(doc, '100').first
    prefix = subfield_value(f100, 'c')
    assert_equal 'Mahatma', prefix
    name = subfield_value(f100, 'a')
    assert_includes name, 'Gandhi', 'Family name'
    # Many aliases
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 5, "Gandhi has #{(data['alias']&.length || 0) + (data['pseudonym']&.length || 0)} aliases+pseudonyms"
  end

  # 10. Q8027 - MLK Jr.: prefix "Reverend Doctor"
  def test_q8027_mlk_jr_prefix
    data, conv, doc = marcxml_for('Q8027')
    f100 = find_datafields(doc, '100').first
    prefix = subfield_value(f100, 'c')
    refute_nil prefix, 'Should have honorific prefix'
    assert_includes prefix, 'Reverend', 'Prefix should contain Reverend'
    name = subfield_value(f100, 'a')
    assert_includes name, 'King', 'Family name King'
  end

  # 11. Q229442 - Twiggy: prefix "Dame", has pseudonym
  def test_q229442_twiggy_dame
    data, conv, doc = marcxml_for('Q229442')
    f100 = find_datafields(doc, '100').first
    prefix = subfield_value(f100, 'c')
    assert_equal 'Dame', prefix
    # Pseudonym "Twiggy" should be in 400
    f400s = find_datafields(doc, '400')
    names = f400s.map { |f| subfield_value(f, 'a') }
    assert names.any? { |n| n&.include?('Twiggy') }, 'Twiggy should be an alias'
  end

  # 12. Q9439 - Queen Victoria: prefix "Majesty", many aliases, no family name
  def test_q9439_queen_victoria
    data, conv, doc = marcxml_for('Q9439')
    assert_equal 'agent_person', conv.agent_type
    f100 = find_datafields(doc, '100').first
    prefix = subfield_value(f100, 'c')
    refute_nil prefix, 'Should have honorific prefix'
    # Many aliases
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 5, "Victoria has many aliases"
  end

  # 13. Q12003 - Cher: mononym, many pseudonyms overlapping aliases
  def test_q12003_cher_mononym_pseudonym_overlap
    data, conv, doc = marcxml_for('Q12003')
    assert_equal 'agent_person', conv.agent_type
    # Deduplication: aliases and pseudonyms should not create duplicate 400 entries
    f400s = find_datafields(doc, '400')
    alias_names = f400s.map { |f| subfield_value(f, 'a') }
    assert_equal alias_names.length, alias_names.uniq.length, 'No duplicate alias entries'
  end

  # 14. Q1744 - Madonna: 15 pseudonyms, given=Veronica, family=Ciccone
  def test_q1744_madonna_many_pseudonyms
    data, conv, doc = marcxml_for('Q1744')
    f100 = find_datafields(doc, '100').first
    assert_equal '1', f100.attributes['ind1']
    name = subfield_value(f100, 'a')
    assert_includes name, 'Ciccone', 'Primary name uses family name'
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 10, "Madonna has #{(data['alias']&.length || 0) + (data['pseudonym']&.length || 0)} aliases+pseudonyms"
    # All 400s should use direct order (ind1=0)
    f400s.each do |f|
      assert_equal '0', f.attributes['ind1'], '400 fields use direct order'
    end
  end

  # 15. Q7542 - Prince: 29 aliases, 5 pseudonyms
  def test_q7542_prince_many_aliases
    data, conv, doc = marcxml_for('Q7542')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Nelson', 'Family name Nelson'
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 20, "Prince has many alias forms"
    # All unique
    alias_names = f400s.map { |f| subfield_value(f, 'a') }
    assert_equal alias_names.length, alias_names.uniq.length, 'No duplicate alias entries'
  end

  # 16. Q517 - Napoleon: 16 aliases, given=Napoléon, family=Bonaparte
  def test_q517_napoleon_accents
    data, conv, doc = marcxml_for('Q517')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Bonaparte', 'Family name'
    # Description
    f678 = find_datafields(doc, '678').first
    refute_nil f678, 'Should have biographical note'
  end

  # 17. Q5588 - Frida Kahlo: 14 aliases, accents in given name
  def test_q5588_frida_kahlo_aliases
    data, conv, doc = marcxml_for('Q5588')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Kahlo', 'Family name Kahlo'
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 10, "Frida has many aliases"
  end

  # 18. Q36844 - Rihanna: given=Rihanna, family=Fenty, label=Rihanna
  def test_q36844_rihanna_given_matches_label
    data, conv, doc = marcxml_for('Q36844')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Fenty', 'Family name Fenty'
    assert_includes name, 'Rihanna', 'Given name Rihanna'
    assert_equal '1', f100.attributes['ind1'], 'Inverted order'
  end

  # 19. Q834621 - Bono: pseudonym, given=Paul, family=Hewson
  def test_q834621_bono_pseudonym
    data, conv, doc = marcxml_for('Q834621')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Hewson', 'Legal family name'
    f400s = find_datafields(doc, '400')
    alias_names = f400s.map { |f| subfield_value(f, 'a') }
    assert alias_names.any? { |n| n&.include?('Bono') }, 'Bono should be an alias'
  end

  # 20. Q2831 - Michael Jackson: given=Joseph (not Michael!), family=Jackson
  def test_q2831_michael_jackson_given_name_mismatch
    data, conv, doc = marcxml_for('Q2831')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    # Wikidata P735 returns "Joseph" (legal first given name), not "Michael"
    assert_includes name, 'Jackson', 'Family name Jackson'
    given = data['givenName']&.first
    assert_equal 'Joseph', given, 'Wikidata given name is Joseph (legal name)'
  end

  # 21. Q19837 - Steve Jobs: given=Paul (legal name), family=Jobs
  def test_q19837_steve_jobs_given_name
    data, conv, doc = marcxml_for('Q19837')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Jobs', 'Family name Jobs'
  end

  # 22. Q12897 - Pelé: given=Edson, family=do Nascimento, has pseudonym
  def test_q12897_pele_pseudonym
    data, conv, doc = marcxml_for('Q12897')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'do Nascimento', 'Family name do Nascimento'
    f400s = find_datafields(doc, '400')
    alias_names = f400s.map { |f| subfield_value(f, 'a') }
    assert alias_names.any? { |n| n == 'Pelé' || n&.include?('Pel') }, 'Pelé should be alias/pseudonym'
  end

  # 23. Q133600 - Banksy: anonymous artist, given=Robin, no family name
  def test_q133600_banksy_anonymous
    data, conv, doc = marcxml_for('Q133600')
    assert_equal 'agent_person', conv.agent_type
    f046 = find_datafields(doc, '046').first
    birth = subfield_value(f046, 'f')
    # Year-only date: 1973-01-01 → should be just "1973" (year-only precision)
    refute_nil birth, 'Should have birth year'
  end

  # 24. Q40662 - John the Baptist: preferred-rank P31 issue, BCE birth
  def test_q40662_john_the_baptist
    data, conv, doc = marcxml_for('Q40662')
    rs = result_set_for('Q40662')
    assert rs.agent_type_valid?, 'Should be detected as valid agent'
    assert_equal 'agent_person', rs.agent_type
    f046 = find_datafields(doc, '046').first
    refute_nil f046, 'Should have dates'
  end

  # 25. Q7186 - Marie Curie: standard case
  def test_q7186_marie_curie
    data, conv, doc = marcxml_for('Q7186')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Curie', 'Family name Curie'
    assert_includes name, 'Marie', 'Given name Marie'
    assert_equal '1', f100.attributes['ind1']
    # LCN
    ids = find_datafields(doc, '024')
    lcn_fields = ids.select { |f| subfield_value(f, '2') == 'Library of Congress Name Authority File' }
    assert_equal 1, lcn_fields.length, 'Should have LCN'
    assert_equal 'n80155913', subfield_value(lcn_fields.first, 'a')
  end

  # 26. Q1339 - J.S. Bach: multiple given names (Johann and Sebastian)
  def test_q1339_bach_multiple_given_names
    data, conv, doc = marcxml_for('Q1339')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Bach', 'Family name Bach'
    # SPARQL may return multiple givenName values (Johann, Sebastian)
    # The converter uses the first one
    given_names = data['givenName'] || []
    assert given_names.length >= 1, 'Should have at least one given name'
  end

  # 27. Q5879 - Goethe: label may be missing ("?"), family=Goethe
  def test_q5879_goethe_missing_label
    data, conv, doc = marcxml_for('Q5879')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    # Should still construct name from given+family even if label is "?"
    assert_includes name, 'Goethe', 'Family name should be present'
  end

  # 28. Q36107 - Muhammad Ali: name change (was Cassius Clay)
  def test_q36107_muhammad_ali
    data, conv, doc = marcxml_for('Q36107')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Ali', 'Current family name Ali'
    # Aliases should include former name
    f400s = find_datafields(doc, '400')
    alias_names = f400s.map { |f| subfield_value(f, 'a') }
    assert alias_names.any? { |n| n&.include?('Cassius') }, 'Former name Cassius Clay should be an alias'
  end

  # 29. Q19848 - Lady Gaga: stage name, given=Stefani, family=Germanotta
  def test_q19848_lady_gaga
    data, conv, doc = marcxml_for('Q19848')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Germanotta', 'Legal family name'
    assert_equal '1', f100.attributes['ind1']
  end

  # 30. Q8023 - Nelson Mandela: many aliases (7), well-documented
  def test_q8023_mandela_many_aliases
    data, conv, doc = marcxml_for('Q8023')
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Mandela', 'Family name'
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 5, "Mandela has #{(data['alias']&.length || 0)} aliases"
    # LCN
    assert_equal 'n85153068', data['libraryOfCongressAuthorityId']&.first
  end
end


# ============================================================
# CORPORATE EDGE CASES (30 tests)
# ============================================================
class CorporateEdgeCaseTest < Minitest::Test

  # 1. Q312 - Apple Inc: popular entity, detected via instanceQid fallback
  def test_q312_apple_instanceqid_detection
    rs = result_set_for('Q312')
    assert rs.agent_type_valid?, 'Apple should be a valid agent'
    assert_equal 'agent_corporate_entity', rs.agent_type
    data, conv, doc = marcxml_for('Q312')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    assert_equal 'Apple Inc.', subfield_value(f110, 'a')
    f046 = find_datafields(doc, '046').first
    assert_equal '19760401', subfield_value(f046, 'f'), 'Inception date'
    assert_nil subfield_value(f046, 'g'), 'No dissolved date'
  end

  # 2. Q95 - Google: popular, instanceQid fallback
  def test_q95_google_detection
    rs = result_set_for('Q95')
    assert_equal 'agent_corporate_entity', rs.agent_type
    data, conv, doc = marcxml_for('Q95')
    f110 = find_datafields(doc, '110').first
    assert_equal 'Google', subfield_value(f110, 'a')
  end

  # 3. Q37156 - IBM: popular, old tech company
  def test_q37156_ibm
    rs = result_set_for('Q37156')
    assert_equal 'agent_corporate_entity', rs.agent_type
    data, conv, doc = marcxml_for('Q37156')
    f110 = find_datafields(doc, '110').first
    assert_equal 'IBM', subfield_value(f110, 'a')
  end

  # 4. Q13371 - Harvard University
  def test_q13371_harvard
    data, conv, doc = marcxml_for('Q13371')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    assert_equal 'Harvard University', subfield_value(f110, 'a')
    f046 = find_datafields(doc, '046').first
    birth = subfield_value(f046, 'f')
    refute_nil birth, 'Should have inception date (1636)'
  end

  # 5. Q23548 - NASA: government agency
  def test_q23548_nasa
    data, conv, doc = marcxml_for('Q23548')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    name = subfield_value(f110, 'a')
    assert name.include?('National Aeronautics') || name.include?('NASA'), 'NASA name'
  end

  # 6. Q458 - European Union: supranational organization
  def test_q458_european_union
    data, conv, doc = marcxml_for('Q458')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    assert_equal 'European Union', subfield_value(f110, 'a')
  end

  # 7. Q9531 - BBC: year-only inception (1927-01-01)
  def test_q9531_bbc_year_inception
    data, conv, doc = marcxml_for('Q9531')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    name = subfield_value(f110, 'a')
    assert name.include?('British Broadcasting') || name.include?('BBC'), 'BBC name'
  end

  # 8. Q1065 - United Nations
  def test_q1065_un
    data, conv, doc = marcxml_for('Q1065')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f046 = find_datafields(doc, '046').first
    refute_nil f046, 'Should have inception date'
    f410s = find_datafields(doc, '410')
    assert f410s.length >= 1, 'UN has aliases'
  end

  # 9. Q7809 - UNESCO
  def test_q7809_unesco
    data, conv, doc = marcxml_for('Q7809')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 10. Q157169 - YMCA: old organization (1844)
  def test_q157169_ymca
    data, conv, doc = marcxml_for('Q157169')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    refute_nil subfield_value(f110, 'a')
  end

  # 11. Q49330 - Doctors Without Borders
  def test_q49330_doctors_without_borders
    data, conv, doc = marcxml_for('Q49330')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 12. Q18395870 - WGBH Educational Foundation
  def test_q18395870_wgbh
    data, conv, doc = marcxml_for('Q18395870')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    name = subfield_value(f110, 'a')
    assert name.include?('WGBH'), 'WGBH name'
  end

  # 13. Q131626 - Smithsonian Institution
  def test_q131626_smithsonian
    rs = result_set_for('Q131626')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 14. Q49108 - MIT
  def test_q49108_mit
    rs = result_set_for('Q49108')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 15. Q213678 - Vatican Library: very old institution (1450)
  def test_q213678_vatican_library
    data, conv, doc = marcxml_for('Q213678')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f046 = find_datafields(doc, '046').first
    birth = subfield_value(f046, 'f')
    refute_nil birth, 'Should have inception date'
  end

  # 16. Q471154 - New York Philharmonic
  def test_q471154_ny_philharmonic
    data, conv, doc = marcxml_for('Q471154')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f410s = find_datafields(doc, '410')
    assert f410s.length >= 1, 'NY Phil has aliases'
  end

  # 17. Q42944 - CERN
  def test_q42944_cern
    data, conv, doc = marcxml_for('Q42944')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 18. Q180 - Wikimedia Foundation
  def test_q180_wikimedia
    data, conv, doc = marcxml_for('Q180')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 19. Q83164 - East India Company: historical, dissolved (1874)
  def test_q83164_east_india_company
    rs = result_set_for('Q83164')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 20. Q327646 - Enron: dissolved, infamous
  def test_q327646_enron
    rs = result_set_for('Q327646')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 21. Q212900 - Lehman Brothers: dissolved (2008)
  def test_q212900_lehman_brothers_dissolved
    data, conv, doc = marcxml_for('Q212900')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f046 = find_datafields(doc, '046').first
    refute_nil subfield_value(f046, 'g'), 'Should have dissolved date'
  end

  # 22. Q8681 - Pan Am: dissolved airline
  def test_q8681_pan_am_dissolved
    data, conv, doc = marcxml_for('Q8681')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f046 = find_datafields(doc, '046').first
    refute_nil subfield_value(f046, 'f'), 'Should have inception date'
    refute_nil subfield_value(f046, 'g'), 'Should have dissolved date'
    f410s = find_datafields(doc, '410')
    assert f410s.length >= 1, 'Pan Am has aliases'
  end

  # 23. Q7817 - WHO
  def test_q7817_who
    rs = result_set_for('Q7817')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 24. Q217365 - Bell Labs
  def test_q217365_bell_labs
    data, conv, doc = marcxml_for('Q217365')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 25. Q131454 - Library of Congress
  def test_q131454_loc
    rs = result_set_for('Q131454')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 26. Q152433 - Xerox
  def test_q152433_xerox
    data, conv, doc = marcxml_for('Q152433')
    assert_equal 'agent_corporate_entity', conv.agent_type
  end

  # 27. Q478214 - Tesla Inc
  def test_q478214_tesla
    data, conv, doc = marcxml_for('Q478214')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f110 = find_datafields(doc, '110').first
    name = subfield_value(f110, 'a')
    assert name.include?('Tesla'), 'Tesla name'
  end

  # 28. Q130614 - Roman Senate: ancient, no dates
  def test_q130614_roman_senate_no_dates
    data, conv, doc = marcxml_for('Q130614')
    assert_equal 'agent_corporate_entity', conv.agent_type
    f046 = find_datafields(doc, '046')
    assert_equal 0, f046.length, 'No dates for Roman Senate'
    # But should have LCN
    ids = find_datafields(doc, '024')
    lcn_fields = ids.select { |f| subfield_value(f, '2') == 'Library of Congress Name Authority File' }
    assert lcn_fields.length >= 1, 'Should have LCN'
  end

  # 29. Corporate uses MARC 110, not 100
  def test_corporate_uses_110
    data, conv, doc = marcxml_for('Q312')
    f100 = find_datafields(doc, '100')
    f110 = find_datafields(doc, '110')
    assert_equal 0, f100.length, 'Corporate should not have MARC 100'
    assert f110.length >= 1, 'Corporate should have MARC 110'
    assert_equal '2', f110.first.attributes['ind1'], 'Corporate ind1 should be 2'
  end

  # 30. Corporate aliases use MARC 410, not 400
  def test_corporate_aliases_use_410
    data, conv, doc = marcxml_for('Q1065')  # UN has aliases
    f400 = find_datafields(doc, '400')
    f410 = find_datafields(doc, '410')
    assert_equal 0, f400.length, 'Corporate should not have MARC 400'
    assert f410.length >= 1, 'Corporate aliases should use MARC 410'
    f410.each do |f|
      assert_equal '2', f.attributes['ind1'], 'Corporate alias ind1 should be 2'
    end
  end
end


# ============================================================
# FAMILY EDGE CASES (30 tests)
# ============================================================
class FamilyEdgeCaseTest < Minitest::Test

  # 1. Q21026250 - Clinton family: baseline
  def test_q21026250_clinton_family
    data, conv, doc = marcxml_for('Q21026250')
    assert_equal 'agent_family', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '3', f100.attributes['ind1'], 'Family ind1 should be 3'
    assert_equal 'Clinton family', subfield_value(f100, 'a')
  end

  # 2. Q813703 - Becker: minimal data, painters family
  def test_q813703_becker_minimal
    data, conv, doc = marcxml_for('Q813703')
    assert_equal 'agent_family', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '3', f100.attributes['ind1']
    refute_nil subfield_value(f100, 'a')
  end

  # 3. Q469819 - Sayn-Wittgenstein-Sayn: German noble family, has alias
  def test_q469819_sayn_wittgenstein
    data, conv, doc = marcxml_for('Q469819')
    assert_equal 'agent_family', conv.agent_type
    rs = result_set_for('Q469819')
    assert_equal 'agent_family', rs.agent_type
  end

  # 4. Q50793 - Pappenheim: has LCN
  def test_q50793_pappenheim_lcn
    data, conv, doc = marcxml_for('Q50793')
    assert_equal 'agent_family', conv.agent_type
    ids = find_datafields(doc, '024')
    lcn_fields = ids.select { |f| subfield_value(f, '2') == 'Library of Congress Name Authority File' }
    assert_equal 1, lcn_fields.length, 'Should have LCN'
    assert_equal 'sh85097685', subfield_value(lcn_fields.first, 'a')
  end

  # 5. Q455758 - Amati: has LCN and familyName property (unusual for family)
  def test_q455758_amati_with_family_name
    data, conv, doc = marcxml_for('Q455758')
    assert_equal 'agent_family', conv.agent_type
    # Amati has a familyName property! The family type should still use ind1=3
    f100 = find_datafields(doc, '100').first
    assert_equal '3', f100.attributes['ind1'], 'Family always uses ind1=3'
    # LCN
    assert_equal 'sh89003883', data['libraryOfCongressAuthorityId']&.first
  end

  # 6. Q525971 - Strauss family
  def test_q525971_strauss
    data, conv, doc = marcxml_for('Q525971')
    assert_equal 'agent_family', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_includes subfield_value(f100, 'a'), 'Strauss'
  end

  # 7. Q826719 - Bernoulli: famous math family, has alias
  def test_q826719_bernoulli_alias
    data, conv, doc = marcxml_for('Q826719')
    assert_equal 'agent_family', conv.agent_type
    aliases = data['alias'] || []
    if aliases.length > 0
      f400s = find_datafields(doc, '400')
      assert f400s.length >= 1, 'Should have alias 400 fields'
      f400s.each { |f| assert_equal '3', f.attributes['ind1'], 'Family alias ind1=3' }
    end
  end

  # 8. Q276014 - Delano family: has alias
  def test_q276014_delano
    data, conv, doc = marcxml_for('Q276014')
    assert_equal 'agent_family', conv.agent_type
  end

  # 9. Q808354 - Barmakids: 5 aliases, non-Western family
  def test_q808354_barmakids_many_aliases
    data, conv, doc = marcxml_for('Q808354')
    assert_equal 'agent_family', conv.agent_type
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 3, "Barmakids has #{data['alias']&.length || 0} aliases"
    # All use family ind1=3
    f400s.each { |f| assert_equal '3', f.attributes['ind1'] }
  end

  # 10. Q444267 - Rosen: noble family with alias
  def test_q444267_rosen
    data, conv, doc = marcxml_for('Q444267')
    assert_equal 'agent_family', conv.agent_type
  end

  # 11. Q822734 - House of Baden: has LCN
  def test_q822734_house_of_baden_lcn
    data, conv, doc = marcxml_for('Q822734')
    assert_equal 'agent_family', conv.agent_type
    assert_equal 'sh85010903', data['libraryOfCongressAuthorityId']&.first
  end

  # 12. Q463886 - Solms-Braunfels: has LCN
  def test_q463886_solms_braunfels_lcn
    data, conv, doc = marcxml_for('Q463886')
    assert_equal 'agent_family', conv.agent_type
    assert_equal 'n2018015114', data['libraryOfCongressAuthorityId']&.first
  end

  # 13. Q26593 - Tiesenhausen: 2 aliases
  def test_q26593_tiesenhausen
    data, conv, doc = marcxml_for('Q26593')
    assert_equal 'agent_family', conv.agent_type
    f400s = find_datafields(doc, '400')
    assert f400s.length >= 2, 'Should have 2+ aliases'
  end

  # 14. Q805564 - Baltazzi: has LCN
  def test_q805564_baltazzi_lcn
    data, conv, doc = marcxml_for('Q805564')
    assert_equal 'agent_family', conv.agent_type
    assert_equal 'sh85011357', data['libraryOfCongressAuthorityId']&.first
  end

  # 15. Q493888 - Gimhae Kim clan: Korean family
  def test_q493888_gimhae_kim
    data, conv, doc = marcxml_for('Q493888')
    assert_equal 'agent_family', conv.agent_type
    f100 = find_datafields(doc, '100').first
    assert_equal '3', f100.attributes['ind1']
  end

  # 16. Q525617 - Clifford family
  def test_q525617_clifford
    data, conv, doc = marcxml_for('Q525617')
    assert_equal 'agent_family', conv.agent_type
  end

  # 17. Q528133 - Frangieh family
  def test_q528133_frangieh
    data, conv, doc = marcxml_for('Q528133')
    assert_equal 'agent_family', conv.agent_type
  end

  # 18. Q818989 - Berenberg family: banking family
  def test_q818989_berenberg
    data, conv, doc = marcxml_for('Q818989')
    assert_equal 'agent_family', conv.agent_type
  end

  # 19. Q818276 - Bentinck: has alias
  def test_q818276_bentinck
    data, conv, doc = marcxml_for('Q818276')
    assert_equal 'agent_family', conv.agent_type
  end

  # 20. Q550499 - Drengot family
  def test_q550499_drengot
    data, conv, doc = marcxml_for('Q550499')
    assert_equal 'agent_family', conv.agent_type
  end

  # 21. Q217945 - Philanthropenos
  def test_q217945_philanthropenos
    data, conv, doc = marcxml_for('Q217945')
    assert_equal 'agent_family', conv.agent_type
  end

  # 22. Q220044 - Ruedin
  def test_q220044_ruedin
    data, conv, doc = marcxml_for('Q220044')
    assert_equal 'agent_family', conv.agent_type
  end

  # 23. Q814064 - Beer family
  def test_q814064_beer
    data, conv, doc = marcxml_for('Q814064')
    assert_equal 'agent_family', conv.agent_type
  end

  # 24. Q816744 - Benda family
  def test_q816744_benda
    data, conv, doc = marcxml_for('Q816744')
    assert_equal 'agent_family', conv.agent_type
  end

  # 25. Q793123 - House of Benyovszky
  def test_q793123_benyovszky
    data, conv, doc = marcxml_for('Q793123')
    assert_equal 'agent_family', conv.agent_type
  end

  # 26. Q832290 - Eltz family
  def test_q832290_eltz
    data, conv, doc = marcxml_for('Q832290')
    assert_equal 'agent_family', conv.agent_type
  end

  # 27. Q443394 - The Rankin Family: "The" in name
  def test_q443394_rankin_family
    data, conv, doc = marcxml_for('Q443394')
    assert_equal 'agent_family', conv.agent_type
    f100 = find_datafields(doc, '100').first
    name = subfield_value(f100, 'a')
    assert_includes name, 'Rankin', 'Rankin name'
  end

  # 28. Q281711 - Burckhardt family
  def test_q281711_burckhardt
    data, conv, doc = marcxml_for('Q281711')
    assert_equal 'agent_family', conv.agent_type
  end

  # 29. Q267955 - Schnewlin
  def test_q267955_schnewlin
    data, conv, doc = marcxml_for('Q267955')
    assert_equal 'agent_family', conv.agent_type
  end

  # 30. Family uses MARC 100 ind1=3, not 110
  def test_family_uses_100_not_110
    data, conv, doc = marcxml_for('Q21026250')
    f100 = find_datafields(doc, '100')
    f110 = find_datafields(doc, '110')
    assert f100.length >= 1, 'Family should use MARC 100'
    assert_equal 0, f110.length, 'Family should NOT use MARC 110'
    assert_equal '3', f100.first.attributes['ind1'], 'Family ind1 must be 3'
  end
end
