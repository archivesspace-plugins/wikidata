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

def agent_for(qid)
  data = load_edge_case(qid)
  agent = WikidataToAgent.new(data, qid)
  h = agent.to_agent_hash
  [data, agent, h]
end

def result_set_for(qid)
  data = load_edge_case(qid)
  bindings = []
  data.each do |prop_name, values|
    Array(values).each do |val|
      bindings << {
        'propertyName' => { 'type' => 'literal', 'value' => prop_name },
        'value' => { 'type' => 'literal', 'value' => val.to_s }
      }
    end
  end
  sparql_json = { 'results' => { 'bindings' => bindings } }
  WikidataResultSet.new(sparql_json, qid)
end

def primary_name_hash(h)
  (h[:names] || []).first || {}
end

def alias_name_hashes(h)
  (h[:names] || [])[1..] || []
end

def dig_date_struct(h)
  d = (h[:dates_of_existence] || []).first
  return nil unless d
  d["structured_date_range"] || d["structured_date_single"]
end

def begin_date_value(h)
  sd = dig_date_struct(h)
  return nil unless sd
  if sd[:jsonmodel_type] == 'structured_date_range'
    sd[:begin_date_standardized] || sd[:begin_date_expression]
  else
    return nil if sd[:date_role] == 'end'
    sd[:date_standardized] || sd[:date_expression]
  end
end

def end_date_value(h)
  sd = dig_date_struct(h)
  return nil unless sd
  if sd[:jsonmodel_type] == 'structured_date_range'
    sd[:end_date_standardized] || sd[:end_date_expression]
  else
    return nil if sd[:date_role] == 'begin'
    sd[:date_standardized] || sd[:date_expression]
  end
end

def naf_identifier(h)
  (h[:agent_record_identifiers] || []).find { |id| id[:source] == 'naf' }
end


# ============================================================
# PERSON EDGE CASES (30 tests)
# ============================================================
class PersonEdgeCaseTest < Minitest::Test

  # 1. Q42 - Douglas Adams: baseline person with all fields
  def test_q42_douglas_adams_baseline
    data, agent, h = agent_for('Q42')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'inverted', pn[:name_order], 'Inverted order for person with family name'
    assert_equal 'Adams', pn[:primary_name]
    assert_equal 'Douglas', pn[:rest_of_name]
    # Dates
    assert_equal '1952-03-11', begin_date_value(h), 'Full birth date'
    assert_equal '2001-05-11', end_date_value(h), 'Full death date'
    # Identifiers
    ids = h[:agent_record_identifiers] || []
    assert ids.length >= 2, 'Should have Wikidata QID + NAF identifiers'
  end

  # 2. Q76 - Barack Obama: missing label, living person (no death date)
  def test_q76_obama_missing_label
    data, agent, h = agent_for('Q76')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || pn[:sort_name] || '', 'Obama'
    assert_includes pn[:rest_of_name] || pn[:sort_name] || '', 'Barack'
    # No death date
    refute_nil begin_date_value(h), 'Should have birth date'
    assert_nil end_date_value(h), 'Living person should have no death date'
  end

  # 3. Q1413 - Nero: ancient person, NO given/family name properties
  def test_q1413_nero_no_name_parts
    data, agent, h = agent_for('Q1413')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'direct', pn[:name_order], 'Direct order when no family name'
    assert_equal 'Nero', pn[:primary_name], 'Falls back to label'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 3, "Nero has #{data['alias']&.length || 0} aliases"
  end

  # 4. Q4604 - Confucius: BCE dates (-0550, -0478)
  def test_q4604_confucius_bce_dates
    data, agent, h = agent_for('Q4604')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'inverted', pn[:name_order]
    assert_includes pn[:primary_name] || '', 'Kong', 'Family name Kong'
    refute_nil begin_date_value(h), 'Should have birth date even for BCE'
  end

  # 5. Q859 - Plato: BCE dates, no family name, single given name
  def test_q859_plato_bce_no_family
    data, agent, h = agent_for('Q859')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    refute_nil pn[:primary_name]
  end

  # 6. Q868 - Aristotle: BCE dates, no family name
  def test_q868_aristotle_bce
    data, agent, h = agent_for('Q868')
    assert_equal 'agent_person', h[:jsonmodel_type]
    rs = result_set_for('Q868')
    assert rs.agent_type_valid?
    assert_equal 'Aristotle', rs.label
  end

  # 7. Q9068 - Voltaire: pseudonym IS the known name, no family name
  def test_q9068_voltaire_pseudonym_as_name
    data, agent, h = agent_for('Q9068')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    refute_nil pn[:primary_name]
    # Pseudonyms should appear as alias names
    aliases = alias_name_hashes(h)
    assert aliases.any? { |n| n[:primary_name]&.include?('Voltaire') }, 'Voltaire should be listed as alias'
  end

  # 8. Q80 - Tim Berners-Lee: honorific prefix "Sir"
  def test_q80_berners_lee_prefix_sir
    data, agent, h = agent_for('Q80')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'Sir', pn[:prefix], 'Honorific prefix should be present'
    assert_nil end_date_value(h), 'Living person should have no death date'
  end

  # 9. Q1001 - Gandhi: honorific prefix "Mahatma"
  def test_q1001_gandhi_prefix_mahatma
    data, agent, h = agent_for('Q1001')
    pn = primary_name_hash(h)
    assert_equal 'Mahatma', pn[:prefix]
    assert_includes pn[:primary_name] || '', 'Gandhi', 'Family name'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 5
  end

  # 10. Q8027 - MLK Jr.: prefix "Reverend Doctor"
  def test_q8027_mlk_jr_prefix
    data, agent, h = agent_for('Q8027')
    pn = primary_name_hash(h)
    refute_nil pn[:prefix], 'Should have honorific prefix'
    assert_includes pn[:prefix], 'Reverend', 'Prefix should contain Reverend'
    assert_includes pn[:primary_name] || '', 'King', 'Family name King'
  end

  # 11. Q229442 - Twiggy: prefix "Dame", has pseudonym
  def test_q229442_twiggy_dame
    data, agent, h = agent_for('Q229442')
    pn = primary_name_hash(h)
    assert_equal 'Dame', pn[:prefix]
    aliases = alias_name_hashes(h)
    assert aliases.any? { |n| n[:primary_name]&.include?('Twiggy') }, 'Twiggy should be an alias'
  end

  # 12. Q9439 - Queen Victoria: prefix "Majesty", many aliases
  def test_q9439_queen_victoria
    data, agent, h = agent_for('Q9439')
    assert_equal 'agent_person', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    refute_nil pn[:prefix], 'Should have honorific prefix'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 5, 'Victoria has many aliases'
  end

  # 13. Q12003 - Cher: mononym, many pseudonyms overlapping aliases
  def test_q12003_cher_mononym_pseudonym_overlap
    data, agent, h = agent_for('Q12003')
    assert_equal 'agent_person', h[:jsonmodel_type]
    aliases = alias_name_hashes(h)
    alias_names = aliases.map { |n| n[:primary_name] }
    assert_equal alias_names.length, alias_names.uniq.length, 'No duplicate alias entries'
  end

  # 14. Q1744 - Madonna: 15 pseudonyms, given=Veronica, family=Ciccone
  def test_q1744_madonna_many_pseudonyms
    data, agent, h = agent_for('Q1744')
    pn = primary_name_hash(h)
    assert_equal 'inverted', pn[:name_order]
    assert_includes pn[:primary_name] || '', 'Ciccone', 'Primary name uses family name'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 10, "Madonna has #{(data['alias']&.length || 0) + (data['pseudonym']&.length || 0)} aliases+pseudonyms"
    # All aliases use direct order
    aliases.each do |n|
      assert_equal 'direct', n[:name_order], '400 fields use direct order'
    end
  end

  # 15. Q7542 - Prince: 29 aliases, 5 pseudonyms
  def test_q7542_prince_many_aliases
    data, agent, h = agent_for('Q7542')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Nelson', 'Family name Nelson'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 20, 'Prince has many alias forms'
    alias_names = aliases.map { |n| n[:primary_name] }
    assert_equal alias_names.length, alias_names.uniq.length, 'No duplicate alias entries'
  end

  # 16. Q517 - Napoleon: 16 aliases, given=Napoléon, family=Bonaparte
  def test_q517_napoleon_accents
    data, agent, h = agent_for('Q517')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Bonaparte', 'Family name'
    # Description note
    refute h[:notes].empty?, 'Should have biographical note'
  end

  # 17. Q5588 - Frida Kahlo: 14 aliases, accents in given name
  def test_q5588_frida_kahlo_aliases
    data, agent, h = agent_for('Q5588')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Kahlo', 'Family name Kahlo'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 10, 'Frida has many aliases'
  end

  # 18. Q36844 - Rihanna: given=Rihanna, family=Fenty, label=Rihanna
  def test_q36844_rihanna_given_matches_label
    data, agent, h = agent_for('Q36844')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Fenty', 'Family name Fenty'
    assert_includes pn[:rest_of_name] || '', 'Rihanna', 'Given name Rihanna'
    assert_equal 'inverted', pn[:name_order]
  end

  # 19. Q834621 - Bono: pseudonym, given=Paul, family=Hewson
  def test_q834621_bono_pseudonym
    data, agent, h = agent_for('Q834621')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Hewson', 'Legal family name'
    aliases = alias_name_hashes(h)
    assert aliases.any? { |n| n[:primary_name]&.include?('Bono') }, 'Bono should be an alias'
  end

  # 20. Q2831 - Michael Jackson: given=Joseph (not Michael!), family=Jackson
  def test_q2831_michael_jackson_given_name_mismatch
    data, agent, h = agent_for('Q2831')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Jackson', 'Family name Jackson'
    given = data['givenName']&.first
    assert_equal 'Joseph', given, 'Wikidata given name is Joseph (legal name)'
  end

  # 21. Q19837 - Steve Jobs: given=Paul (legal name), family=Jobs
  def test_q19837_steve_jobs_given_name
    data, agent, h = agent_for('Q19837')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Jobs', 'Family name Jobs'
  end

  # 22. Q12897 - Pelé: given=Edson, family=do Nascimento, has pseudonym
  def test_q12897_pele_pseudonym
    data, agent, h = agent_for('Q12897')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'do Nascimento', 'Family name do Nascimento'
    aliases = alias_name_hashes(h)
    assert aliases.any? { |n| n[:primary_name] == 'Pelé' || n[:primary_name]&.include?('Pel') }, 'Pelé should be alias/pseudonym'
  end

  # 23. Q133600 - Banksy: anonymous artist, given=Robin, no family name
  def test_q133600_banksy_anonymous
    data, agent, h = agent_for('Q133600')
    assert_equal 'agent_person', h[:jsonmodel_type]
    refute_nil begin_date_value(h), 'Should have birth year'
  end

  # 24. Q40662 - John the Baptist: preferred-rank P31 issue, BCE birth
  def test_q40662_john_the_baptist
    data, agent, h = agent_for('Q40662')
    rs = result_set_for('Q40662')
    assert rs.agent_type_valid?, 'Should be detected as valid agent'
    assert_equal 'agent_person', rs.agent_type
    assert_equal 'agent_person', h[:jsonmodel_type]
    refute_nil begin_date_value(h), 'Should have dates'
  end

  # 25. Q7186 - Marie Curie: standard case
  def test_q7186_marie_curie
    data, agent, h = agent_for('Q7186')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Curie', 'Family name Curie'
    assert_includes pn[:rest_of_name] || '', 'Marie', 'Given name Marie'
    assert_equal 'inverted', pn[:name_order]
    naf = naf_identifier(h)
    refute_nil naf, 'Should have NAF identifier'
    assert_equal 'n80155913', naf[:record_identifier]
  end

  # 26. Q1339 - J.S. Bach: multiple given names (Johann and Sebastian)
  def test_q1339_bach_multiple_given_names
    data, agent, h = agent_for('Q1339')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Bach', 'Family name Bach'
    given_names = data['givenName'] || []
    assert given_names.length >= 1, 'Should have at least one given name'
  end

  # 27. Q5879 - Goethe: label may be missing ("?"), family=Goethe
  def test_q5879_goethe_missing_label
    data, agent, h = agent_for('Q5879')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Goethe', 'Family name should be present'
  end

  # 28. Q36107 - Muhammad Ali: name change (was Cassius Clay)
  def test_q36107_muhammad_ali
    data, agent, h = agent_for('Q36107')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Ali', 'Current family name Ali'
    aliases = alias_name_hashes(h)
    assert aliases.any? { |n| n[:primary_name]&.include?('Cassius') }, 'Former name Cassius Clay should be an alias'
  end

  # 29. Q19848 - Lady Gaga: stage name, given=Stefani, family=Germanotta
  def test_q19848_lady_gaga
    data, agent, h = agent_for('Q19848')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Germanotta', 'Legal family name'
    assert_equal 'inverted', pn[:name_order]
  end

  # 30. Q8023 - Nelson Mandela: many aliases (7), well-documented
  def test_q8023_mandela_many_aliases
    data, agent, h = agent_for('Q8023')
    pn = primary_name_hash(h)
    assert_includes pn[:primary_name] || '', 'Mandela', 'Family name'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 5, "Mandela has #{data['alias']&.length || 0} aliases"
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
    data, agent, h = agent_for('Q312')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'Apple Inc.', pn[:primary_name]
    assert_equal '1976-04-01', begin_date_value(h), 'Inception date'
    assert_nil end_date_value(h), 'No dissolved date'
  end

  # 2. Q95 - Google: popular, instanceQid fallback
  def test_q95_google_detection
    rs = result_set_for('Q95')
    assert_equal 'agent_corporate_entity', rs.agent_type
    data, agent, h = agent_for('Q95')
    pn = primary_name_hash(h)
    assert_equal 'Google', pn[:primary_name]
  end

  # 3. Q37156 - IBM: popular, old tech company
  def test_q37156_ibm
    rs = result_set_for('Q37156')
    assert_equal 'agent_corporate_entity', rs.agent_type
    data, agent, h = agent_for('Q37156')
    pn = primary_name_hash(h)
    assert_equal 'IBM', pn[:primary_name]
  end

  # 4. Q13371 - Harvard University
  def test_q13371_harvard
    data, agent, h = agent_for('Q13371')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'Harvard University', pn[:primary_name]
    refute_nil begin_date_value(h), 'Should have inception date (1636)'
  end

  # 5. Q23548 - NASA: government agency
  def test_q23548_nasa
    data, agent, h = agent_for('Q23548')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert pn[:primary_name].include?('National Aeronautics') || pn[:primary_name].include?('NASA'), 'NASA name'
  end

  # 6. Q458 - European Union: supranational organization
  def test_q458_european_union
    data, agent, h = agent_for('Q458')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'European Union', pn[:primary_name]
  end

  # 7. Q9531 - BBC: year-only inception (1927-01-01)
  def test_q9531_bbc_year_inception
    data, agent, h = agent_for('Q9531')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert pn[:primary_name].include?('British Broadcasting') || pn[:primary_name].include?('BBC'), 'BBC name'
  end

  # 8. Q1065 - United Nations
  def test_q1065_un
    data, agent, h = agent_for('Q1065')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    refute_nil begin_date_value(h), 'Should have inception date'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 1, 'UN has aliases'
  end

  # 9. Q7809 - UNESCO
  def test_q7809_unesco
    data, agent, h = agent_for('Q7809')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
  end

  # 10. Q157169 - YMCA: old organization (1844)
  def test_q157169_ymca
    data, agent, h = agent_for('Q157169')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    refute_nil pn[:primary_name]
  end

  # 11. Q49330 - Doctors Without Borders
  def test_q49330_doctors_without_borders
    data, agent, h = agent_for('Q49330')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
  end

  # 12. Q18395870 - WGBH Educational Foundation
  def test_q18395870_wgbh
    data, agent, h = agent_for('Q18395870')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert pn[:primary_name].include?('WGBH'), 'WGBH name'
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
    data, agent, h = agent_for('Q213678')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    refute_nil begin_date_value(h), 'Should have inception date'
  end

  # 16. Q471154 - New York Philharmonic
  def test_q471154_ny_philharmonic
    data, agent, h = agent_for('Q471154')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    aliases = alias_name_hashes(h)
    assert aliases.length >= 1, 'NY Phil has aliases'
  end

  # 17. Q42944 - CERN
  def test_q42944_cern
    data, agent, h = agent_for('Q42944')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
  end

  # 18. Q180 - Wikimedia Foundation
  def test_q180_wikimedia
    data, agent, h = agent_for('Q180')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
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
    data, agent, h = agent_for('Q212900')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    refute_nil end_date_value(h), 'Should have dissolved date'
  end

  # 22. Q8681 - Pan Am: dissolved airline
  def test_q8681_pan_am_dissolved
    data, agent, h = agent_for('Q8681')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    refute_nil begin_date_value(h), 'Should have inception date'
    refute_nil end_date_value(h), 'Should have dissolved date'
    aliases = alias_name_hashes(h)
    assert aliases.length >= 1, 'Pan Am has aliases'
  end

  # 23. Q7817 - WHO
  def test_q7817_who
    rs = result_set_for('Q7817')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 24. Q217365 - Bell Labs
  def test_q217365_bell_labs
    data, agent, h = agent_for('Q217365')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
  end

  # 25. Q131454 - Library of Congress
  def test_q131454_loc
    rs = result_set_for('Q131454')
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  # 26. Q152433 - Xerox
  def test_q152433_xerox
    data, agent, h = agent_for('Q152433')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
  end

  # 27. Q478214 - Tesla Inc
  def test_q478214_tesla
    data, agent, h = agent_for('Q478214')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert pn[:primary_name].include?('Tesla'), 'Tesla name'
  end

  # 28. Q130614 - Roman Senate: ancient, no dates
  def test_q130614_roman_senate_no_dates
    data, agent, h = agent_for('Q130614')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    assert_nil begin_date_value(h), 'No dates for Roman Senate'
    naf = naf_identifier(h)
    refute_nil naf, 'Should have NAF identifier'
  end

  # 29. Corporate names use name_corporate_entity jsonmodel_type
  def test_corporate_uses_name_corporate_entity
    data, agent, h = agent_for('Q312')
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    h[:names].each do |n|
      assert_equal 'name_corporate_entity', n[:jsonmodel_type], 'All names should be name_corporate_entity'
    end
  end

  # 30. Corporate alias names also use name_corporate_entity
  def test_corporate_alias_names_use_corporate_type
    data, agent, h = agent_for('Q1065')  # UN has aliases
    aliases = alias_name_hashes(h)
    assert aliases.length >= 1, 'UN has aliases'
    aliases.each do |n|
      assert_equal 'name_corporate_entity', n[:jsonmodel_type], 'Corporate aliases use name_corporate_entity'
    end
  end
end


# ============================================================
# FAMILY EDGE CASES (30 tests)
# ============================================================
class FamilyEdgeCaseTest < Minitest::Test

  # 1. Q21026250 - Clinton family: baseline
  def test_q21026250_clinton_family
    data, agent, h = agent_for('Q21026250')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'name_family', pn[:jsonmodel_type], 'Family name type'
    assert_equal 'Clinton family', pn[:family_name]
  end

  # 2. Q813703 - Becker: minimal data, painters family
  def test_q813703_becker_minimal
    data, agent, h = agent_for('Q813703')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'name_family', pn[:jsonmodel_type]
    refute_nil pn[:family_name]
  end

  # 3. Q469819 - Sayn-Wittgenstein-Sayn: German noble family, has alias
  def test_q469819_sayn_wittgenstein
    data, agent, h = agent_for('Q469819')
    assert_equal 'agent_family', h[:jsonmodel_type]
    rs = result_set_for('Q469819')
    assert_equal 'agent_family', rs.agent_type
  end

  # 4. Q50793 - Pappenheim: has NAF
  def test_q50793_pappenheim_lcn
    data, agent, h = agent_for('Q50793')
    assert_equal 'agent_family', h[:jsonmodel_type]
    naf = naf_identifier(h)
    refute_nil naf, 'Should have NAF identifier'
    assert_equal 'sh85097685', naf[:record_identifier]
  end

  # 5. Q455758 - Amati: has NAF and familyName property (unusual for family)
  def test_q455758_amati_with_family_name
    data, agent, h = agent_for('Q455758')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'name_family', pn[:jsonmodel_type], 'Family always uses name_family'
    assert_equal 'sh89003883', data['libraryOfCongressAuthorityId']&.first
  end

  # 6. Q525971 - Strauss family
  def test_q525971_strauss
    data, agent, h = agent_for('Q525971')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_includes pn[:family_name] || '', 'Strauss'
  end

  # 7. Q826719 - Bernoulli: famous math family, has alias
  def test_q826719_bernoulli_alias
    data, agent, h = agent_for('Q826719')
    assert_equal 'agent_family', h[:jsonmodel_type]
    aliases = data['alias'] || []
    if aliases.length > 0
      alias_hashes = alias_name_hashes(h)
      assert alias_hashes.length >= 1, 'Should have aliases'
      alias_hashes.each { |n| assert_equal 'name_family', n[:jsonmodel_type], 'Family alias type' }
    end
  end

  # 8. Q276014 - Delano family: has alias
  def test_q276014_delano
    data, agent, h = agent_for('Q276014')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 9. Q808354 - Barmakids: 5 aliases, non-Western family
  def test_q808354_barmakids_many_aliases
    data, agent, h = agent_for('Q808354')
    assert_equal 'agent_family', h[:jsonmodel_type]
    aliases = alias_name_hashes(h)
    assert aliases.length >= 3, "Barmakids has #{data['alias']&.length || 0} aliases"
    aliases.each { |n| assert_equal 'name_family', n[:jsonmodel_type] }
  end

  # 10. Q444267 - Rosen: noble family with alias
  def test_q444267_rosen
    data, agent, h = agent_for('Q444267')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 11. Q822734 - House of Baden: has NAF
  def test_q822734_house_of_baden_lcn
    data, agent, h = agent_for('Q822734')
    assert_equal 'agent_family', h[:jsonmodel_type]
    assert_equal 'sh85010903', data['libraryOfCongressAuthorityId']&.first
  end

  # 12. Q463886 - Solms-Braunfels: has NAF
  def test_q463886_solms_braunfels_lcn
    data, agent, h = agent_for('Q463886')
    assert_equal 'agent_family', h[:jsonmodel_type]
    assert_equal 'n2018015114', data['libraryOfCongressAuthorityId']&.first
  end

  # 13. Q26593 - Tiesenhausen: 2 aliases
  def test_q26593_tiesenhausen
    data, agent, h = agent_for('Q26593')
    assert_equal 'agent_family', h[:jsonmodel_type]
    aliases = alias_name_hashes(h)
    assert aliases.length >= 2, 'Should have 2+ aliases'
  end

  # 14. Q805564 - Baltazzi: has NAF
  def test_q805564_baltazzi_lcn
    data, agent, h = agent_for('Q805564')
    assert_equal 'agent_family', h[:jsonmodel_type]
    assert_equal 'sh85011357', data['libraryOfCongressAuthorityId']&.first
  end

  # 15. Q493888 - Gimhae Kim clan: Korean family
  def test_q493888_gimhae_kim
    data, agent, h = agent_for('Q493888')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_equal 'name_family', pn[:jsonmodel_type]
  end

  # 16. Q525617 - Clifford family
  def test_q525617_clifford
    data, agent, h = agent_for('Q525617')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 17. Q528133 - Frangieh family
  def test_q528133_frangieh
    data, agent, h = agent_for('Q528133')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 18. Q818989 - Berenberg family: banking family
  def test_q818989_berenberg
    data, agent, h = agent_for('Q818989')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 19. Q818276 - Bentinck: has alias
  def test_q818276_bentinck
    data, agent, h = agent_for('Q818276')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 20. Q550499 - Drengot family
  def test_q550499_drengot
    data, agent, h = agent_for('Q550499')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 21. Q217945 - Philanthropenos
  def test_q217945_philanthropenos
    data, agent, h = agent_for('Q217945')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 22. Q220044 - Ruedin
  def test_q220044_ruedin
    data, agent, h = agent_for('Q220044')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 23. Q814064 - Beer family
  def test_q814064_beer
    data, agent, h = agent_for('Q814064')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 24. Q816744 - Benda family
  def test_q816744_benda
    data, agent, h = agent_for('Q816744')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 25. Q793123 - House of Benyovszky
  def test_q793123_benyovszky
    data, agent, h = agent_for('Q793123')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 26. Q832290 - Eltz family
  def test_q832290_eltz
    data, agent, h = agent_for('Q832290')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 27. Q443394 - The Rankin Family: "The" in name
  def test_q443394_rankin_family
    data, agent, h = agent_for('Q443394')
    assert_equal 'agent_family', h[:jsonmodel_type]
    pn = primary_name_hash(h)
    assert_includes pn[:family_name] || '', 'Rankin', 'Rankin name'
  end

  # 28. Q281711 - Burckhardt family
  def test_q281711_burckhardt
    data, agent, h = agent_for('Q281711')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 29. Q267955 - Schnewlin
  def test_q267955_schnewlin
    data, agent, h = agent_for('Q267955')
    assert_equal 'agent_family', h[:jsonmodel_type]
  end

  # 30. Family names use name_family jsonmodel_type, not name_corporate_entity
  def test_family_uses_name_family_type
    data, agent, h = agent_for('Q21026250')
    assert_equal 'agent_family', h[:jsonmodel_type]
    h[:names].each do |n|
      assert_equal 'name_family', n[:jsonmodel_type], 'Family names should use name_family'
    end
  end
end
