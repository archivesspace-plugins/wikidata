# Wikidata search implementation.
# Uses wbsearchentities for search and wbgetentities for full entity data.
# TODO: implement search, results_to_marcxml_file, and Wikidata→MARCXML conversion
class WikidataSearcher

  WIKIDATA_API = 'https://www.wikidata.org/w/api.php'

  def search(query, page, records_per_page)
    # TODO: call wbsearchentities, parse response, return WikidataResultSet
    raise NotImplementedError, "Wikidata search not yet implemented"
  end

  def results_to_marcxml_file(qids)
    # TODO: call wbgetentities for each qid, convert to MARCXML, split agents/subjects
    raise NotImplementedError, "Wikidata import not yet implemented"
  end
end
