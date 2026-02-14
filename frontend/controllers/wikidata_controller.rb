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

    render :json => results.to_json
  end


  def import
    # TODO: implement import via WikidataSearcher#results_to_marcxml_file
    render :json => {'error' => 'Import not yet implemented'}
  end


  private

  def do_search(params)
    searcher.search(params[:q], params[:page].to_i, params[:records_per_page].to_i)
  end


  def searcher
    WikidataSearcher.new
  end
end
