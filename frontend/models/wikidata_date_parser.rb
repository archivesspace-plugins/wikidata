# Shared date parsing for Wikidata date values.
# Used by both WikidataToMarcxml and WikidataToAgent.
module WikidataDateParser
  module_function

  # Normalise a Wikidata date string to a compact form:
  #   "+1952-03-11T00:00:00Z" → "19520311"  (full date)
  #   "+1960-06-00T00:00:00Z" → "196006"    (year-month)
  #   "+1960-00-00T00:00:00Z" → "1960"      (year only)
  #   "-0550-01-01T00:00:00Z" → "-0550"     (BCE)
  #   "1952"                  → "1952"       (plain year)
  # Returns nil for blank or unparseable input.
  def parse_wikidata_date(val)
    return nil if val.nil? || val.to_s.strip.empty?
    s = val.to_s.strip
    if m = s.match(/^([+-]?)(\d{4})-(\d{2})-(\d{2})/)
      sign, y, mo, d = m[1], m[2], m[3], m[4]
      prefix = (sign == '-') ? '-' : ''
      return "#{prefix}#{y}#{mo}#{d}" if mo != '00' && d != '00'
      return "#{prefix}#{y}#{mo}" if mo != '00'
      return "#{prefix}#{y}"
    end
    if m = s.match(/^([+-]?)(\d{4})/)
      sign, y = m[1], m[2]
      prefix = (sign == '-') ? '-' : ''
      return "#{prefix}#{y}"
    end
    nil
  end
end
