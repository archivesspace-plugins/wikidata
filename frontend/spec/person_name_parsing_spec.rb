require_relative 'spec_helper'

# Person name parsing: prefer the item label as the authoritative full name,
# rendered in indirect (family, given) order, using the family name only to
# split the label. Covers the cases reported during beta testing.
class PersonNameParsingTest < Minitest::Test

  def person_name(data, qid = 'Q1')
    data = { 'isHuman' => ['true'] }.merge(data)
    WikidataToAgent.new(data, qid).to_agent_hash[:names].first
  end

  # Q2278761 (Sylvia Rivera): label "Sylvia Rivera", family Rivera, given Sylvia.
  # Must NOT put the full label in primary with the given duplicated in rest.
  def test_label_given_family_splits_on_family
    n = person_name('label' => ['Sylvia Rivera'], 'familyName' => ['Rivera'], 'givenName' => ['Sylvia'])
    assert_equal 'Rivera',         n[:primary_name]
    assert_equal 'Sylvia',         n[:rest_of_name]
    assert_equal 'inverted',       n[:name_order]
    assert_equal 'Rivera, Sylvia', n[:sort_name]
  end

  # Q29452333 (Sabra Moore): only a family-name triple, but a complete label.
  # The label should be used to derive the given portion.
  def test_family_only_with_label_derives_given_from_label
    n = person_name('label' => ['Sabra Moore'], 'familyName' => ['Moore'])
    assert_equal 'Moore',        n[:primary_name]
    assert_equal 'Sabra',        n[:rest_of_name]
    assert_equal 'inverted',     n[:name_order]
    assert_equal 'Moore, Sabra', n[:sort_name]
  end

  # Q189080 (Lou Reed): label "Lou Reed", family Reed, multiple given names
  # (Louis #1, Allen #2). The label must win over the ambiguous P735 values.
  def test_multiple_given_names_uses_label_not_p735
    n = person_name('label'      => ['Lou Reed'],
                    'familyName' => ['Reed'],
                    'givenName'  => ['Louis', 'Allen'])
    assert_equal 'Reed',      n[:primary_name]
    assert_equal 'Lou',       n[:rest_of_name]
    assert_equal 'Reed, Lou', n[:sort_name]
  end

  # Q134990179 (Sara Gilfert): label "Sara Gilfert", given Sara, family Gilfert.
  def test_given_and_family_present_with_label
    n = person_name('label' => ['Sara Gilfert'], 'givenName' => ['Sara'], 'familyName' => ['Gilfert'])
    assert_equal 'Gilfert', n[:primary_name]
    assert_equal 'Sara',    n[:rest_of_name]
    assert_equal 'inverted', n[:name_order]
  end

  # Family name present but not a suffix of the label (e.g. label is a stage
  # name): fall back to the given-name triple for the rest.
  def test_family_not_in_label_falls_back_to_given
    n = person_name('label' => ['Pelé'], 'familyName' => ['do Nascimento'], 'givenName' => ['Edson'])
    assert_equal 'do Nascimento',        n[:primary_name]
    assert_equal 'Edson',                n[:rest_of_name]
    assert_equal 'inverted',             n[:name_order]
    assert_equal 'do Nascimento, Edson', n[:sort_name]
  end

  # Mononym / no family name: use the label as primary in direct order.
  def test_no_family_uses_label_direct_order
    n = person_name('label' => ['Nero'])
    assert_equal 'Nero',   n[:primary_name]
    assert_nil   n[:rest_of_name]
    assert_equal 'direct', n[:name_order]
    assert_equal 'Nero',   n[:sort_name]
  end

  # Missing label but family/given present: still produce indirect order.
  def test_missing_label_uses_family_and_given
    n = person_name('familyName' => ['Obama'], 'givenName' => ['Barack'])
    assert_equal 'Obama',         n[:primary_name]
    assert_equal 'Barack',        n[:rest_of_name]
    assert_equal 'Obama, Barack', n[:sort_name]
  end

  # Case-insensitive label/family match still splits correctly.
  def test_case_insensitive_family_split
    n = person_name('label' => ['Ada LOVELACE'], 'familyName' => ['Lovelace'])
    assert_equal 'Lovelace', n[:primary_name]
    assert_equal 'Ada',      n[:rest_of_name]
  end
end
