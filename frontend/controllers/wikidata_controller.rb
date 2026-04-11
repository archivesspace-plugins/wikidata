require 'wikidata_searcher'
require 'securerandom'

class WikidataController < ApplicationController

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

    if qids.empty?
      render :json => { 'error' => I18n.t("plugins.wikidata.messages.none_selected") }, :status => 422
      return
    end

    existing = find_existing_agents(qids)
    if existing.any?
      render :json => { 'already_imported' => existing }, :status => 422
      return
    end

    begin
      agents = searcher.results_to_agents(qids)

      if agents.empty?
        render :json => { 'error' => I18n.t("plugins.wikidata.messages.import_no_agents") }, :status => 422
        return
      end

      created  = []
      existing = []

      agents.each do |entry|
        agent_type  = entry[:agent_hash][:jsonmodel_type]
        agent_model = JSONModel(agent_type.to_sym).from_hash(entry[:agent_hash])

        begin
          agent_model.save
          created << { 'qid' => entry[:qid], 'uri' => frontend_agent_url(agent_model) }
        rescue JSONModel::ValidationException => ve
          # Backend uniqueness constraint fires when Solr hasn't indexed yet
          exceptions = (ve.invalid_object._exceptions rescue {})
          conflicts = Array(exceptions['conflicting_record'])
          if conflicts.any?
            agent_uri  = conflicts.first
            agent_info = JSONModel::HTTP.get_json(agent_uri) rescue nil
            title      = agent_info ? (agent_info['display_name'] || agent_info['title'] || agent_uri) : agent_uri
            existing << { 'qid' => entry[:qid], 'uri' => frontend_uri_from_json_uri(agent_uri), 'title' => title }
          else
            raise
          end
        end
      end

      if existing.any? && created.empty?
        render :json => { 'already_imported' => existing }, :status => 422
      elsif created.any?
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
