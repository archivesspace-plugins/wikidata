require 'wikidata_searcher'
require 'securerandom'

class WikidataController < ApplicationController

  MAX_IMPORT_QIDS = 25

  set_access_control "update_agent_record" => [:search, :index, :import]

  def index
    @page = 1
    @records_per_page = 10

    flash.now[:info] = I18n.t("plugins.wikidata.messages.service_warning")
  end


  def search
    results = do_search(params)

    if results[:error]
      render :json => results, :status => 422
    else
      render :json => results
    end
  end


  def import
    qids = params[:qid] || []
    qids = [qids] unless qids.is_a?(Array)

    # Normalise and validate each QID to a strict Q\d+ format.
    qids = qids.map { |q| WikidataSearcher.extract_qid(q.to_s) }.compact.uniq

    if qids.empty?
      render :json => { 'error' => I18n.t("plugins.wikidata.messages.none_selected") }, :status => 422
      return
    end

    if qids.length > MAX_IMPORT_QIDS
      render :json => { 'error' => "Cannot import more than #{MAX_IMPORT_QIDS} entities at once." }, :status => 422
      return
    end

    begin
      agents = searcher.results_to_agents(qids)

      if agents.empty?
        render :json => { 'error' => I18n.t("plugins.wikidata.messages.import_no_agents") }, :status => 422
        return
      end

      created = []

      # Pre-populate with agents already indexed in Solr (avoids a redundant save attempt).
      find_existing_agents(qids).each do |hit|
        created << { 'qid' => hit['qid'], 'uri' => frontend_uri_from_json_uri(hit['uri']) }
      end

      already_found = created.map { |c| c['qid'] }.to_set

      agents.each do |entry|
        next if already_found.include?(entry[:qid])

        agent_type  = entry[:agent_hash][:jsonmodel_type]
        agent_model = JSONModel(agent_type.to_sym).from_hash(entry[:agent_hash])

        begin
          agent_model.save
          created << { 'qid' => entry[:qid], 'uri' => frontend_agent_url(agent_model) }
        rescue JSONModel::ValidationException => ve
          # Uniqueness conflict when Solr index lags behind the database.
          # Redirect to the existing record just like a successful import.
          exceptions = (ve.invalid_object._exceptions rescue {})
          conflicts  = Array(exceptions['conflicting_record'])
          if conflicts.any?
            created << { 'qid' => entry[:qid], 'uri' => frontend_uri_from_json_uri(conflicts.first) }
          else
            raise
          end
        end
      end

      if created.any?
        render :json => { 'created' => created }
      else
        render :json => { 'error' => I18n.t("plugins.wikidata.messages.import_no_agents") }, :status => 422
      end
    rescue WikidataSearcher::WikidataError => e
      render :json => { 'error' => e.message }, :status => 422
    rescue => e
      Rails.logger.error("Wikidata import error: #{e.message}\n#{e.backtrace.join("\n")}")
      render :json => { 'error' => I18n.t("plugins.wikidata.messages.import_error") + ": #{e.message}" }, :status => 500
    end
  end


  private

  def do_search(params)
    query = params[:q].to_s.strip
    searcher.search(query, params[:page].to_i, params[:records_per_page].to_i)
  rescue WikidataSearcher::WikidataError => e
    { records: [], hit_count: 0, error: e.message }
  end


  def searcher
    WikidataSearcher.new
  end

  BACKEND_TO_FRONTEND_TYPE = {
    'people'             => 'agent_person',
    'families'           => 'agent_family',
    'corporate_entities' => 'agent_corporate_entity'
  }.freeze

  # Convert a saved agent model's backend URI → frontend path
  def frontend_agent_url(agent_model)
    frontend_uri_from_json_uri(agent_model.uri.to_s)
  end

  # Convert backend URI string (/agents/people/42) → frontend path (/agents/agent_person/42)
  def frontend_uri_from_json_uri(uri)
    parts         = uri.to_s.split('/')   # ["", "agents", "people", "42"]
    backend_type  = parts[2]
    id            = parts[3]
    frontend_type = BACKEND_TO_FRONTEND_TYPE[backend_type] || backend_type
    url_for(:controller => :agents, :action => :show,
            :agent_type => frontend_type, :id => id)
  end

  def find_existing_agents(qids)
    agent_types = %w[agent_person agent_family agent_corporate_entity]
    existing = []

    qids.each do |qid|
      qid = qid.to_s.strip.upcase
      qid = "Q#{qid}" unless qid.start_with?('Q')
      next unless qid.match?(/\AQ\d+\z/)

      results = JSONModel::HTTP.get_json('/search', {
        'q' => "authority_id:#{qid}",
        'type[]' => agent_types,
        'page' => 1
      })

      next unless results && results['total_hits'].to_i > 0

      hit = results['results'].first
      existing << {
        'qid' => qid,
        'uri' => hit['uri'],
        'title' => hit['title']
      }
    end

    existing
  end
end
