require_relative 'spec_helper'
require_searcher

# results_to_agents fetches each Q ID independently and reports per-item
# failures instead of silently dropping them or aborting the whole batch.
class ImportResultsTest < Minitest::Test

  # Build a WikidataResultSet from a simple propertyName => [values] dict.
  def result_set_with(props, qid)
    bindings = []
    props.each do |name, values|
      Array(values).each do |v|
        bindings << { 'propertyName' => { 'value' => name }, 'value' => { 'value' => v.to_s } }
      end
    end
    WikidataResultSet.new({ 'results' => { 'bindings' => bindings } }, qid)
  end

  # Stub fetch_entity per Q ID: valid person, fetch error, invalid entity, no data.
  def searcher_for(behaviour)
    s = WikidataSearcher.new
    s.define_singleton_method(:fetch_entity) do |q|
      qid = WikidataSearcher.extract_qid(q)
      r = behaviour[qid]
      raise WikidataSearcher::WikidataError, 'timeout' if r == :error
      r
    end
    s
  end

  def test_one_failure_does_not_abort_the_batch
    valid   = result_set_with({ 'label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'] }, 'Q1')
    invalid = result_set_with({ 'label' => ['Some Concept'] }, 'Q3') # no type → not an agent

    result = searcher_for('Q1' => valid, 'Q2' => :error, 'Q3' => invalid)
             .results_to_agents(%w[Q1 Q2 Q3])

    assert_equal ['Q1'], result[:agents].map { |a| a[:qid] }, 'valid agent still built despite a sibling failure'
    assert_equal 'agent_person', result[:agents].first[:agent_hash][:jsonmodel_type]
    assert_equal %w[Q2 Q3], result[:failed].map { |f| f['qid'] }.sort
  end

  def test_failure_reasons_are_descriptive
    invalid = result_set_with({ 'label' => ['Some Concept'] }, 'Q3')
    result  = searcher_for('Q2' => :error, 'Q3' => invalid).results_to_agents(%w[Q2 Q3])

    by_qid = result[:failed].each_with_object({}) { |f, h| h[f['qid']] = f['reason'] }
    assert_match(/Could not retrieve from Wikidata/, by_qid['Q2'])
    assert_match(/Not a person, family, or corporate body/, by_qid['Q3'])
  end

  def test_nil_result_reported_as_no_data
    result = searcher_for('Q9' => nil).results_to_agents(%w[Q9])
    assert_empty result[:agents]
    assert_equal 'Q9', result[:failed].first['qid']
    assert_match(/No data returned/, result[:failed].first['reason'])
  end

  def test_all_valid_has_no_failures
    valid = result_set_with({ 'label' => ['Jane Doe'], 'familyName' => ['Doe'], 'isHuman' => ['true'] }, 'Q1')
    result = searcher_for('Q1' => valid).results_to_agents(%w[Q1])
    assert_equal ['Q1'], result[:agents].map { |a| a[:qid] }
    assert_empty result[:failed]
  end
end
