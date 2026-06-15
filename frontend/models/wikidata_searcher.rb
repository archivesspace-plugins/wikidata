# Wikidata entity lookup via SPARQL API.
# User input: URL (https://www.wikidata.org/wiki/Q42) or Q ID (Q42).
# Fetches entity data and converts to ArchivesSpace agent JSON for import.
require 'ashttp'
require_relative 'wikidata_sparql_query'
require_relative 'wikidata_result_set'
require_relative 'wikidata_to_agent'
require 'asutils'

class WikidataSearcher

  SPARQL_ENDPOINT = 'https://query.wikidata.org/sparql'
  # Required by Wikidata: https://meta.wikimedia.org/wiki/User-Agent_policy
  USER_AGENT = 'ArchivesSpace-Wikidata-Plugin/1.0 (https://github.com/archivesspace-plugins/wikidata)'

  class WikidataError < StandardError; end

  # Process-wide cache of raw SPARQL response bodies, keyed by query text, so a
  # search preview and a subsequent import (or a retry) don't re-run the same
  # query against the rate-limited endpoint. Short TTL keeps data reasonably fresh.
  CACHE_TTL = 300 # seconds
  @response_cache = {}
  @cache_mutex = Mutex.new

  class << self
    attr_reader :response_cache, :cache_mutex
  end

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

  # Full entity lookup (all fields) for import. Returns WikidataResultSet or nil.
  def fetch_entity(qid_or_url)
    qid = self.class.extract_qid(qid_or_url)
    return nil if qid.nil?
    WikidataResultSet.new(fetch_cached(WikidataSparqlQuery.query_for(qid)), qid)
  end

  # Lightweight lookup for the search preview (label/description/type only).
  def fetch_preview(qid_or_url)
    qid = self.class.extract_qid(qid_or_url)
    return nil if qid.nil?
    WikidataResultSet.new(fetch_cached(WikidataSparqlQuery.preview_query_for(qid)), qid)
  end

  # Search: for this plugin, "search" means lookup by URL/Q ID.
  # Returns JSON structure compatible with frontend (records array).
  def search(query, page = 1, records_per_page = 10)
    result_set = fetch_preview(query)
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

  # Convert selected Q IDs directly to ArchivesSpace agent JSON hashes.
  # Returns an array of { qid:, agent_hash: } objects for API creation.
  def results_to_agents(qids)
    Array(qids).compact.filter_map do |qid_param|
      qid = self.class.extract_qid(qid_param)
      next if qid.nil?

      result_set = fetch_entity(qid)
      next if result_set.nil? || !result_set.valid? || !result_set.agent_type_valid?

      converter = WikidataToAgent.new(result_set.data, qid)
      { qid: qid, agent_hash: converter.to_agent_hash }
    end
  end

  private

  # Returns the SPARQL response body for a query, using a short-lived
  # process-wide cache. The query text is the cache key, so preview and full
  # queries are cached independently.
  def fetch_cached(query)
    now = Time.now

    self.class.cache_mutex.synchronize do
      entry = self.class.response_cache[query]
      return entry[:body] if entry && (now - entry[:ts]) < CACHE_TTL
    end

    body = fetch_sparql(build_uri(query))

    self.class.cache_mutex.synchronize do
      cache = self.class.response_cache
      cache[query] = { body: body, ts: now }
      # Bound the cache and drop stale entries.
      cache.delete_if { |_q, e| (now - e[:ts]) >= CACHE_TTL } if cache.size > 256
    end

    body
  end

  def build_uri(query)
    uri = URI(SPARQL_ENDPOINT)
    uri.query = URI.encode_www_form(query: query, format: 'json')
    uri
  end

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
