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
      # For BCE dates, always return year-only since full dates are usually approximate
      return "#{prefix}#{y}" if sign == '-'
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

  # Format a parsed date value for display in date_expression.
  # Converts compact forms to human-readable strings:
  #   "19520311" → "1952-03-11"
  #   "196006"   → "1960-06"
  #   "1960"     → "1960"
  #   "-0550"    → "550 BCE"
  # Returns the original value if unparseable.
  def format_date_for_display(val)
    return val if val.nil?
    s = val.to_s.strip
    return s if s.empty?

    # BCE dates
    if s.start_with?('-')
      year_str = s[1..-1]  # Remove the minus sign
      if year_str.match?(/^\d{4}$/)
        # Remove leading zeros for BCE years
        year_num = year_str.to_i
        return "#{year_num} BCE"
      end
    end

    # CE dates
    if s.match?(/^\d{8}$/)  # YYYYMMDD
      y = s[0..3]
      m = s[4..5]
      d = s[6..7]
      return "#{y}-#{m}-#{d}"
    elsif s.match?(/^\d{6}$/)  # YYYYMM
      y = s[0..3]
      m = s[4..5]
      return "#{y}-#{m}"
    elsif s.match?(/^\d{4}$/)  # YYYY
      return s
    end

    # Fallback
    s
  end
end
