require_relative 'spec_helper'

class WikidataSparqlQueryTest < Minitest::Test

  def test_replaces_placeholder_with_qid
    query = WikidataSparqlQuery.query_for('Q42')
    refute_match(/Q_PLACEHOLDER/, query)
    assert_match(/wd:Q42/, query)
  end

  def test_normalizes_qid_to_uppercase
    query = WikidataSparqlQuery.query_for('q42')
    assert_match(/wd:Q42/, query)
  end

  def test_adds_q_prefix_if_missing
    query = WikidataSparqlQuery.query_for('42')
    assert_match(/wd:Q42/, query)
  end

  # Verify all required property blocks are present

  def test_includes_given_name_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P735/, query, 'Missing given name (P735)')
    assert_match(/"givenName"/, query)
  end

  def test_includes_family_name_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P734/, query, 'Missing family name (P734)')
    assert_match(/"familyName"/, query)
  end

  def test_includes_generational_suffix_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P8017/, query, 'Missing generational suffix (P8017)')
    assert_match(/"generationalSuffix"/, query)
  end

  def test_includes_honorific_prefix_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P511/, query, 'Missing honorific prefix (P511)')
    assert_match(/"honorificPrefix"/, query)
  end

  def test_includes_pseudonym_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P742/, query, 'Missing pseudonym (P742)')
    assert_match(/"pseudonym"/, query)
  end

  def test_includes_date_of_birth_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P569/, query, 'Missing date of birth (P569)')
  end

  def test_includes_date_of_death_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P570/, query, 'Missing date of death (P570)')
  end

  def test_includes_inception_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P571/, query, 'Missing inception (P571)')
  end

  def test_includes_dissolved_date_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P576/, query, 'Missing dissolved date (P576)')
  end

  def test_includes_label_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/rdfs:label/, query, 'Missing label')
    assert_match(/"label"/, query)
  end

  def test_includes_description_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/schema:description/, query, 'Missing description')
    assert_match(/"description"/, query)
  end

  def test_includes_identifier_blocks
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wdt:P244/, query, 'Missing LCN (P244)')
    assert_match(/wdt:P3430/, query, 'Missing SNAC (P3430)')
    assert_match(/wdt:P214/, query, 'Missing VIAF (P214)')
  end

  def test_includes_entity_type_detection
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/wd:Q5/, query, 'Missing human detection (Q5)')
    assert_match(/wd:Q8436/, query, 'Missing family detection (Q8436)')
    assert_match(/"isHuman"/, query)
    assert_match(/"isFamily"/, query)
    assert_match(/"instanceQid"/, query, 'Missing instanceQid block for org type fallback')
  end

  # Regression: type detection must use p:P31/ps:P31 (all statement ranks) not wdt:P31
  # (best-rank only). Entities like Q40662 have P31=Q5 at normal rank — wdt:P31 skips it.
  def test_type_detection_uses_all_statement_ranks
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/p:P31\/ps:P31/, query, 'Type detection must use p:P31/ps:P31 to cover non-preferred rank statements')
  end

  # The query should NOT use wdt:P279* property paths for corporate detection
  # (they cause timeouts for popular entities like Apple, Google)
  def test_no_property_path_for_corporate_detection
    query = WikidataSparqlQuery.query_for('Q42')
    refute_match(/P279\*\s+wd:Q131085629/, query, 'Should not use P279* for corporate detection (causes timeouts)')
  end

  def test_includes_alias_block
    query = WikidataSparqlQuery.query_for('Q42')
    assert_match(/skos:altLabel/, query, 'Missing alias/altLabel block')
    assert_match(/"alias"/, query)
  end
end
