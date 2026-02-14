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

    begin
      parse_results = searcher.results_to_marcxml_file(qids)

      if parse_results[:agents][:count] > 0
        marcxml_file = parse_results[:agents][:file]

        agents_job = Job.new("import_job", {
                             "import_type" => "marcxml_auth_agent",
                             "jsonmodel_type" => "import_job",
                             "import_subjects" => nil
                            },
                      {"wikidata_import_#{SecureRandom.uuid}" => marcxml_file})

        agents_job_response = agents_job.upload
        render :json => { 'job_uri' => url_for(:controller => :jobs, :action => :show, :id => agents_job_response['id']) }
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
  end


  def searcher
    WikidataSearcher.new
  end
end
