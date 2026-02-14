# Parses wbsearchentities JSON response and provides same structure as OpenSearchResultSet.
# TODO: implement to match OpenSearchResultSet#to_json shape for frontend compatibility
class WikidataResultSet

  attr_reader :total_results
  attr_reader :start_index
  attr_reader :items_per_page
  attr_reader :entries

  def initialize(response_body, query)
    @entries = []
    @query = query
    # TODO: parse JSON, populate @entries with title, qid, uri
    # TODO: set pagination fields
  end

  def to_json
    # TODO: return same structure as OpenSearchResultSet
    raise NotImplementedError, "WikidataResultSet#to_json not yet implemented"
  end
end
