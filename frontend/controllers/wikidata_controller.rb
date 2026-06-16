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
      result = searcher.results_to_agents(qids)
      agents = result[:agents]
      failed = result[:failed]   # [{ 'qid' =>, 'reason' => }] from the fetch/build phase

      created = []

      # Agents already indexed in Solr — skip a redundant save and mark as existing.
      # Validate that each Solr hit actually exists in the database (handles index lag).
      find_existing_agents(qids).each do |hit|
        agent_info = JSONModel::HTTP.get_json(hit['uri']) rescue nil
        created << make_created(hit['qid'], hit['uri'], hit['title'] || agent_info['title'], true) if agent_info
      end
      already_found = created.map { |c| c['qid'] }.to_set

      # Save each built agent independently: one failure must not abort the batch.
      agents.each do |entry|
        next if already_found.include?(entry[:qid])

        begin
          agent_model = JSONModel(entry[:agent_hash][:jsonmodel_type].to_sym).from_hash(entry[:agent_hash])
          agent_model.save
          created << make_created(entry[:qid], agent_model.uri.to_s, agent_display_title(entry[:agent_hash]))
        rescue JSONModel::ValidationException, JSON::ValidationException => ve
          # A uniqueness conflict means the agent already exists; anything else is a
          # genuine failure for this one record.
          existing = resolve_conflict(entry[:qid], ve)
          if existing
            created << existing
          else
            failed << { 'qid' => entry[:qid], 'reason' => validation_message(ve) }
          end
        rescue => e
          Rails.logger.error("Wikidata import: failed to save #{entry[:qid]}: #{e.class}: #{e.message}")
          failed << { 'qid' => entry[:qid], 'reason' => e.message }
        end
      end

      if created.any? || failed.any?
        render :json => { 'created' => created, 'failed' => failed }
      else
        render :json => { 'error' => I18n.t("plugins.wikidata.messages.import_no_agents") }, :status => 422
      end
    rescue WikidataSearcher::WikidataError => e
      render :json => { 'error' => e.message }, :status => 422
    rescue => e
      Rails.logger.error("Wikidata import error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
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

  # Build a created-agent entry for the import response: the review (show) URL,
  # the edit URL, and a human-readable title for the summary list.
  def make_created(qid, backend_uri, title, existed = false)
    {
      'qid'      => qid,
      'uri'      => frontend_uri_from_json_uri(backend_uri, :show),
      'edit_uri' => frontend_uri_from_json_uri(backend_uri, :edit),
      'title'    => (title && !title.to_s.strip.empty?) ? title.to_s.strip : qid,
      'existed'  => existed
    }
  end

  # If a save failed on a uniqueness conflict whose conflicting record still
  # exists, return a created-entry pointing at it (existed: true); otherwise nil.
  def resolve_conflict(qid, exception)
    uri = conflicting_record_uri(exception)
    return nil unless uri
    agent_info = JSONModel::HTTP.get_json(uri) rescue nil
    return nil unless agent_info
    make_created(qid, uri, agent_info['title'], true)
  end

  # Extract the conflicting_record URI from a backend validation exception, if any.
  def conflicting_record_uri(ve)
    if ve.respond_to?(:errors) && ve.errors.is_a?(Hash) && ve.errors['conflicting_record']
      return Array(ve.errors['conflicting_record']).first
    end
    if ve.respond_to?(:invalid_object) && ve.invalid_object && ve.invalid_object.respond_to?(:_exceptions)
      data = (ve.invalid_object._exceptions rescue {})
      return Array(data['conflicting_record']).first if data.is_a?(Hash) && data['conflicting_record']
    end
    return $1 if ve.to_s =~ /conflicting_record["\]]*\s*[:=>\s]*["\/]*(\/agents\/[^"\/\s]+\/\d+)/
    nil
  end

  # Human-readable reason from a backend validation exception.
  def validation_message(ve)
    if ve.respond_to?(:errors) && ve.errors.is_a?(Hash) && ve.errors.any?
      ve.errors.map { |field, msgs| "#{field}: #{Array(msgs).join(', ')}" }.join('; ')
    else
      ve.message.to_s
    end
  end

  # Best-effort display title from the agent hash we built for import.
  def agent_display_title(agent_hash)
    name = (agent_hash[:names] || []).first || {}
    name[:sort_name] || name[:primary_name] || name[:family_name] || agent_hash[:jsonmodel_type]
  end

  # Convert backend URI string (/agents/people/42) → frontend path
  # (/agents/agent_person/42), for the given action (:show or :edit).
  def frontend_uri_from_json_uri(uri, action = :show)
    parts         = uri.to_s.split('/')   # ["", "agents", "people", "42"]
    backend_type  = parts[2]
    id            = parts[3]
    frontend_type = BACKEND_TO_FRONTEND_TYPE[backend_type] || backend_type
    url_for(:controller => :agents, :action => action,
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
