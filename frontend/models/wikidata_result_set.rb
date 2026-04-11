# Parses Wikidata SPARQL JSON response and provides structured data for a single entity.
# SPARQL returns: { "results": { "bindings": [ {"propertyName": {...}, "value": {...}} ] } }
class WikidataResultSet

  attr_reader :data
  attr_reader :qid
  attr_reader :error

  def initialize(sparql_json_response, qid)
    @qid = normalize_qid(qid)
    @data = {}
    @error = nil

    return if sparql_json_response.nil? || sparql_json_response.empty?

    begin
      json = sparql_json_response.is_a?(String) ? JSON.parse(sparql_json_response) : sparql_json_response
      bindings = json.dig('results', 'bindings') || []
      bindings.each do |row|
        pname = extract_value(row['propertyName'])
        val = extract_value(row['value'])
        next if pname.nil?
        @data[pname] ||= []
        @data[pname] << val unless val.nil?
      end
    rescue JSON::ParserError => e
      @error = "Failed to parse SPARQL response: #{e.message}"
    end
  end

  def valid?
    @error.nil? && !@data.empty?
  end

  # Known Wikidata types (P31 values) that are subclasses of Q131085629 (collective agent).
  # Used to detect corporate entities when the SPARQL property path times out.
  # This list covers the most common organizational types found on Wikidata.
  KNOWN_ORG_TYPES = %w[
    Q131085629 Q43229 Q4830453 Q783794 Q167037 Q891723 Q484652 Q327333
    Q3918 Q7278 Q163740 Q178706 Q33506 Q7075 Q11032 Q178790 Q35127
    Q1616075 Q294422 Q15911314 Q161726 Q6881511 Q18388277 Q1058914
    Q1335818 Q15936437 Q1752939 Q170156 Q2085381 Q239582 Q245065
    Q2570643 Q319845 Q31855 Q4002648 Q4120211 Q42998 Q46970 Q51647
    Q61766601 Q70441508 Q708676 Q902104 Q11204 Q109909183 Q112572558
    Q1126006 Q11396960 Q11422631 Q115456878 Q1188663 Q1194093
    Q120121699 Q123432 Q1371037 Q1589009 Q15925165 Q17505024
    Q1700154 Q1788992 Q21032622 Q22806 Q23002054 Q23670565
    Q26236686 Q45400320 Q53251146 Q6040928 Q96888669
    Q215380 Q2088357 Q28564 Q215048 Q20639856 Q2001305
    Q8436
  ].freeze

  # Returns agent type only for valid agent entities (person, family, corporate).
  # Returns nil for subjects/concepts (e.g. Q5891 philosophy) that should not be imported as agents.
  def agent_type
    return 'agent_family' if @data['isFamily']&.include?('true')
    return 'agent_person' if @data['isHuman']&.include?('true')
    # Check instanceQid against known organizational types (handles SPARQL timeout)
    instance_qids = @data['instanceQid'] || []
    if instance_qids.any? { |qid| KNOWN_ORG_TYPES.include?(qid) }
      return 'agent_family' if instance_qids.include?('Q8436')
      return 'agent_corporate_entity'
    end
    # Legacy fallback: isCollectiveAgent flag from older SPARQL responses
    return 'agent_corporate_entity' if @data['isCollectiveAgent']&.include?('true')
    nil
  end

  def agent_type_valid?
    !agent_type.nil?
  end

  def label
    @data['label']&.first || @data['qNumber']&.first || @qid
  end

  def description
    @data['description']&.first
  end

  AGENT_TYPE_LABELS = {
    'agent_person' => 'Person',
    'agent_family' => 'Family',
    'agent_corporate_entity' => 'Corporate'
  }.freeze

  def to_preview_hash
    {
      qid: @qid,
      title: label,
      description: description || '',
      agent_type: AGENT_TYPE_LABELS[agent_type] || agent_type,
      agent_type_valid: agent_type_valid?
    }
  end

  private

  def extract_value(node)
    return nil if node.nil?
    return node['value'] if node.is_a?(Hash) && node.key?('value')
    return node['content'] if node.is_a?(Hash) && node.key?('content')
    node.to_s
  end

  def normalize_qid(qid)
    return nil if qid.nil?
    s = qid.to_s.upcase.strip
    s = "Q#{s}" unless s.start_with?('Q')
    s
  end
end
