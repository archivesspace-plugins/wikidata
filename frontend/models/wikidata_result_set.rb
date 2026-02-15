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

  # Returns agent type only for valid agent entities (person, family, corporate).
  # Returns nil for subjects/concepts (e.g. Q5891 philosophy) that should not be imported as agents.
  def agent_type
    return 'agent_family' if @data['isFamily']&.include?('true')
    return 'agent_corporate_entity' if @data['isCollectiveAgent']&.include?('true')
    return 'agent_person' if @data['isHuman']&.include?('true')
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
