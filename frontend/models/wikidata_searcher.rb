# Wikidata entity lookup via SPARQL API.
# User input: URL (https://www.wikidata.org/wiki/Q42) or Q ID (Q42).
# Fetches entity data and converts to MARCXML for ArchivesSpace import.
require 'ashttp'
require 'nokogiri'
require_relative 'wikidata_sparql_query'
require_relative 'wikidata_result_set'
require_relative 'wikidata_to_marcxml'
require 'asutils'

class WikidataSearcher

  SPARQL_ENDPOINT = 'https://query.wikidata.org/sparql'
  # Required by Wikidata: https://meta.wikimedia.org/wiki/User-Agent_policy
  USER_AGENT = 'ArchivesSpace-Wikidata-Plugin/1.0 (https://github.com/archivesspace-plugins/wikidata)'

  class WikidataError < StandardError; end

  # Extract Q ID from URL or plain input.
  # Accepts: "https://www.wikidata.org/wiki/Q42", "Q42", "42"
  def self.extract_qid(input)
    return nil if input.nil? || input.to_s.strip.empty?
    s = input.to_s.strip
    if m = s.match(%r{wikidata\.org/wiki/(Q\d+)}i)
      return m[1].upcase
    end
    if m = s.match(/\b(Q?\d+)\b/i)
      q = m[1].upcase
      q = "Q#{q}" unless q.start_with?('Q')
      return q
    end
    nil
  end

  # Look up a single entity by Q ID or URL. Returns WikidataResultSet or nil.
  def fetch_entity(qid_or_url)
    qid = self.class.extract_qid(qid_or_url)
    return nil if qid.nil?

    query = WikidataSparqlQuery.query_for(qid)
    uri = URI(SPARQL_ENDPOINT)
    uri.query = URI.encode_www_form(query: query, format: 'json')

    body = fetch_sparql(uri)
    WikidataResultSet.new(body, qid)
  end

  # Search: for this plugin, "search" means lookup by URL/Q ID.
  # Returns JSON structure compatible with frontend (records array).
  def search(query, page = 1, records_per_page = 10)
    result_set = fetch_entity(query)
    return error_response('Invalid or missing Wikidata URL or Q ID') if result_set.nil?

    if result_set.error
      return error_response(result_set.error)
    end

    unless result_set.valid?
      return error_response('No data returned from Wikidata for this entity')
    end

    unless result_set.agent_type_valid?
      return error_response('This Wikidata entity is not a person, family, or corporate body. Only agent records can be imported.')
    end

    {
      records: [result_set.to_preview_hash],
      hit_count: 1,
      first_record_index: 1,
      last_record_index: 1,
      page: 1,
      records_per_page: records_per_page,
      at_start: true,
      at_end: true,
      query: query
    }
  end

  # Convert selected Q IDs to MARCXML file for import.
  # Returns { agents: { count: N, file: Tempfile } } - agents only (no subjects per PRD).
  def results_to_marcxml_file(qids)
    agent_tempfile = ASUtils.tempfile('wikidata_import_agent')
    agents_count = 0

    agent_tempfile.write("<collection>\n")

    Array(qids).compact.each do |qid_param|
      qid = self.class.extract_qid(qid_param)
      next if qid.nil?

      result_set = fetch_entity(qid)
      next if result_set.nil? || !result_set.valid? || !result_set.agent_type_valid?

      converter = WikidataToMarcxml.new(result_set.data, qid)
      marcxml = converter.to_marcxml

      # Wrap in record element if not already
      doc = Nokogiri::XML(marcxml)
      record = doc.at_xpath('//record') || doc.root
      agent_tempfile.write(record.to_xml)
      agents_count += 1
    end

    agent_tempfile.write("\n</collection>")
    agent_tempfile.flush
    agent_tempfile.rewind

    {
      agents: { count: agents_count, file: agent_tempfile },
      subjects: { count: 0, file: nil }
    }
  end

  private

  def fetch_sparql(uri)
    ASHTTP.start_uri(uri, :open_timeout => 10, :read_timeout => 30) do |http|
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = USER_AGENT
      response = http.request(request)
      raise WikidataError, "SPARQL request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end
  end

  def error_response(message)
    {
      records: [],
      hit_count: 0,
      first_record_index: 0,
      last_record_index: 0,
      page: 1,
      records_per_page: 10,
      at_start: true,
      at_end: true,
      query: nil,
      error: message
    }
  end
end
