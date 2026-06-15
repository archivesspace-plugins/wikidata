require_relative 'spec_helper'
require_searcher

# The searcher caches raw SPARQL responses process-wide (keyed by query text)
# so a search preview and a later import/retry don't re-hit the rate-limited
# endpoint. Preview and full queries are distinct keys.
class SearchCachingTest < Minitest::Test

  CANNED = JSON.generate(
    'results' => { 'bindings' => [
      { 'propertyName' => { 'value' => 'label' },   'value' => { 'value' => 'Test Person' } },
      { 'propertyName' => { 'value' => 'isHuman' },  'value' => { 'value' => 'true' } }
    ] }
  )

  def setup
    WikidataSearcher.response_cache.clear
  end

  # Stub the network call on an instance and count invocations.
  def searcher_recording(calls)
    s = WikidataSearcher.new
    s.define_singleton_method(:fetch_sparql) { |uri| calls << uri.to_s; CANNED }
    s
  end

  def test_repeated_preview_hits_cache
    calls = []
    s = searcher_recording(calls)
    s.fetch_preview('Q42')
    s.fetch_preview('Q42')
    assert_equal 1, calls.size, 'second identical preview should be served from cache'
  end

  def test_cache_is_shared_across_instances
    calls = []
    searcher_recording(calls).fetch_preview('Q42')
    searcher_recording(calls).fetch_preview('Q42')
    assert_equal 1, calls.size, 'cache should be process-wide, not per-instance'
  end

  def test_preview_and_full_are_cached_separately
    calls = []
    s = searcher_recording(calls)
    s.fetch_preview('Q42')   # preview query
    s.fetch_entity('Q42')    # full query — different text, different key
    assert_equal 2, calls.size, 'preview and full queries are distinct cache entries'
  end

  def test_different_qids_not_conflated
    calls = []
    s = searcher_recording(calls)
    s.fetch_preview('Q42')
    s.fetch_preview('Q937')
    assert_equal 2, calls.size
  end
end
