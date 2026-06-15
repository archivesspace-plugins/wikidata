require_relative 'spec_helper'

# Detection of corporate-body subclasses. Any item whose P31 is zero or more
# `subclass of` steps from corporate body (Q106668099) is importable as a
# corporate entity, even when its specific type is not in KNOWN_ORG_TYPES
# (e.g. Q3269648 non-profit organization, Q334453 division).
class CorporateBodyDetectionTest < Minitest::Test

  def result_set(data)
    bindings = []
    data.each do |prop, values|
      Array(values).each do |val|
        bindings << {
          'propertyName' => { 'type' => 'literal', 'value' => prop },
          'value'        => { 'type' => 'literal', 'value' => val.to_s }
        }
      end
    end
    WikidataResultSet.new({ 'results' => { 'bindings' => bindings } }, 'Q1')
  end

  # Q138534600 (Puerto Rican Association for Community Affairs): P31 = non-profit
  # organization (Q3269648), which is not in KNOWN_ORG_TYPES but is a subclass of
  # corporate body.
  def test_corporate_body_flag_detected_as_corporate
    rs = result_set('label' => ['Puerto Rican Association for Community Affairs'],
                    'instanceQid' => ['Q3269648'],
                    'isCorporateBody' => ['true'])
    assert rs.agent_type_valid?
    assert_equal 'agent_corporate_entity', rs.agent_type
  end

  def test_corporate_body_flag_via_to_agent
    h = WikidataToAgent.new({ 'label' => ['Some Division'], 'isCorporateBody' => ['true'] }, 'Q105027234').to_agent_hash
    assert_equal 'agent_corporate_entity', h[:jsonmodel_type]
    assert_equal 'Some Division', h[:names].first[:primary_name]
  end

  # Family detection must still win over the corporate body flag.
  def test_family_wins_over_corporate_body
    rs = result_set('label' => ['Some family'],
                    'isFamily' => ['true'],
                    'isCorporateBody' => ['true'])
    assert_equal 'agent_family', rs.agent_type
  end

  # Human detection must still win over the corporate body flag.
  def test_human_wins_over_corporate_body
    rs = result_set('label' => ['Some person'],
                    'isHuman' => ['true'],
                    'isCorporateBody' => ['true'])
    assert_equal 'agent_person', rs.agent_type
  end

  # Non-agent entity with neither flag nor known org type is still rejected.
  def test_non_agent_still_rejected
    rs = result_set('label' => ['philosophy'], 'instanceQid' => ['Q12345unknown'])
    assert_nil rs.agent_type
    refute rs.agent_type_valid?
  end
end
