require_relative 'spec_helper'

# Wikidata reports a precision per date value (9 = year, 10 = month, 11 = day).
# The truthy wdt: predicate normalises year/month-precision dates to YYYY-01-01,
# so the parser must use the precision to standardize at the right granularity.
class WikidataDatePrecisionTest < Minitest::Test
  include WikidataDateParser

  # ── parse_wikidata_date with precision ──────────────────────────────────────

  def test_year_precision_truncates_to_year
    assert_equal '1961', parse_wikidata_date('1961-01-01T00:00:00Z', 9)
  end

  def test_month_precision_truncates_to_year_month
    assert_equal '196103', parse_wikidata_date('1961-03-01T00:00:00Z', 10)
  end

  def test_day_precision_keeps_full_date
    assert_equal '19610311', parse_wikidata_date('1961-03-11T00:00:00Z', 11)
  end

  def test_precision_coarser_than_year_falls_back_to_year
    assert_equal '1920', parse_wikidata_date('1920-01-01T00:00:00Z', 8) # decade
  end

  def test_no_precision_preserves_existing_behaviour
    assert_equal '19610311', parse_wikidata_date('1961-03-11T00:00:00Z')
    assert_equal '1961',     parse_wikidata_date('1961-00-00T00:00:00Z')
  end

  def test_blank_precision_string_is_ignored
    assert_equal '19610101', parse_wikidata_date('1961-01-01T00:00:00Z', '')
  end

  def test_bce_stays_year_only_regardless_of_precision
    assert_equal '-0550', parse_wikidata_date('-0550-01-01T00:00:00Z', 11)
  end

  # ── end-to-end through WikidataToAgent ──────────────────────────────────────

  def date_struct(h)
    d = (h[:dates_of_existence] || []).first
    d && (d['structured_date_single'] || d['structured_date_range'])
  end

  def corporate(inception, precision)
    data = { 'label' => ['Some Org'], 'isCorporateBody' => ['true'],
             'inception' => [inception], 'inceptionPrecision' => [precision] }
    WikidataToAgent.new(data, 'Q1').to_agent_hash
  end

  def test_year_precision_inception_is_standardized_as_year
    sd = date_struct(corporate('1961-01-01T00:00:00Z', '9'))
    assert_equal '1961', sd[:date_standardized]
    assert_nil sd[:date_expression]
  end

  def test_month_precision_inception_is_standardized_as_year_month
    sd = date_struct(corporate('1961-03-01T00:00:00Z', '10'))
    assert_equal '1961-03', sd[:date_standardized]
    assert_nil sd[:date_expression]
  end

  def test_day_precision_inception_is_standardized_as_full_date
    sd = date_struct(corporate('1961-03-11T00:00:00Z', '11'))
    assert_equal '1961-03-11', sd[:date_standardized]
    assert_nil sd[:date_expression]
  end
end
