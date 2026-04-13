# Converts a Wikidata SPARQL result set into an ArchivesSpace agent JSON hash
# suitable for direct API creation via JSONModel.
#
# Dates: standardized (YYYY-MM-DD) only when we have full-date precision.
# Year-only and BCE dates are stored as expressions, never as standardized.

require_relative 'wikidata_date_parser'

class WikidataToAgent
  include WikidataDateParser

  SOURCE_MAP = WikidataToMarcxml::SOURCE_MAP

  def initialize(data, qid)
    @data = data
    @qid  = qid.to_s.upcase
    @qid  = "Q#{@qid}" unless @qid.start_with?('Q')
  end

  def agent_type
    @agent_type ||= begin
      tmp = WikidataToMarcxml.new(@data, @qid)
      tmp.agent_type
    end
  end

  def to_agent_hash
    case agent_type
    when 'agent_person'          then build_person
    when 'agent_family'          then build_family
    when 'agent_corporate_entity' then build_corporate
    end
  end

  private

  # ── builders ─────────────────────────────────────────────────────────────

  def build_person
    given  = get('givenName')
    family = get('familyName')
    label  = get('label')
    prefix = get('honorificPrefix')
    suffix = get('generationalSuffix')

    if family || given
      primary  = family || label || @qid
      rest     = given
      order    = 'inverted'
      sort_key = [family, given].compact.join(', ')
    else
      primary  = label || @qid
      rest     = nil
      order    = 'direct'
      sort_key = primary
    end

    name = compact_hash(
      jsonmodel_type: 'name_person',
      primary_name:   primary,
      rest_of_name:   rest,
      prefix:         prefix,
      suffix:         suffix,
      name_order:     order,
      source:         'local',
      rules:          'local',
      sort_name:      sort_key,
      authority_id:   @qid
    )

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_person', primary_name: a,
        name_order: 'direct', source: 'local', rules: 'local', sort_name: a }
    end

    {
      jsonmodel_type:           'agent_person',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(parse_date(get('dateOfBirth')), parse_date(get('dateOfDeath'))),
      notes:                    build_notes
    }
  end

  def build_family
    label = get('label') || @qid
    name  = { jsonmodel_type: 'name_family', family_name: label,
               source: 'local', rules: 'local', sort_name: label,
               authority_id: @qid }

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_family', family_name: a,
        source: 'local', rules: 'local', sort_name: a }
    end

    begin_date = parse_date(get('dateOfBirth')) || parse_date(get('inception'))
    end_date   = parse_date(get('dateOfDeath')) || parse_date(get('dissolvedDate'))

    {
      jsonmodel_type:           'agent_family',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(begin_date, end_date),
      notes:                    build_notes
    }
  end

  def build_corporate
    label = get('label') || @qid
    name  = { jsonmodel_type: 'name_corporate_entity', primary_name: label,
               source: 'local', rules: 'local', sort_name: label,
               authority_id: @qid }

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_corporate_entity', primary_name: a,
        source: 'local', rules: 'local', sort_name: a }
    end

    {
      jsonmodel_type:           'agent_corporate_entity',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(parse_date(get('inception')),
                                             parse_date(get('dissolvedDate'))),
      notes:                    build_notes
    }
  end

  # ── identifiers ──────────────────────────────────────────────────────────

  def build_identifiers
    ids = [{
      primary_identifier: true,
      record_identifier:  @qid,
      source:             'wikidata',
      identifier_type:    'local'
    }]

    SOURCE_MAP.each do |field, source_name|
      val = get(field)
      next if val.nil? || val.strip.empty?
      ids << {
        primary_identifier: false,
        record_identifier:  val.strip,
        source:             source_name,
        identifier_type:    'local'
      }
    end

    ids
  end

  # ── dates ─────────────────────────────────────────────────────────────────
  # Rule: use date_standardized (YYYY-MM-DD) when we have full-date precision.
  # Use date_expression for year-only, BCE, or unparseable values.
  # Never set both for the same date field.

  def build_dates(begin_val, end_val)
    return [] if begin_val.nil? && end_val.nil?

    begin_std  = full_date_iso(begin_val)
    end_std    = full_date_iso(end_val)

    # Only use 'range' when both ends are present
    date_type = (begin_val && end_val) ? 'range' : 'single'

    if date_type == 'single'
      val  = begin_val || end_val
      std  = begin_std || end_std
      role = begin_val ? 'begin' : 'end'

      sd = if std
             { jsonmodel_type: 'structured_date_single', date_role: role,
               date_standardized: std, date_standardized_type: 'standard' }
           else
             { jsonmodel_type: 'structured_date_single', date_role: role,
               date_expression: val.to_s }
           end
    else
      sd = { jsonmodel_type: 'structured_date_range' }

      if begin_std
        sd[:begin_date_standardized]      = begin_std
        sd[:begin_date_standardized_type] = 'standard'
      elsif begin_val
        sd[:begin_date_expression] = begin_val.to_s
      end

      if end_std
        sd[:end_date_standardized]      = end_std
        sd[:end_date_standardized_type] = 'standard'
      elsif end_val
        sd[:end_date_expression] = end_val.to_s
      end
    end

    [{
      jsonmodel_type:               'structured_date_label',
      date_label:                   'existence',
      date_type_structured:         date_type,
      "structured_date_#{date_type}" => sd
    }]
  end

  # Returns "YYYY-MM-DD" (ISO 8601) if the value has full date precision.
  # Input is the output of parse_date/parse_wikidata_date: "YYYYMMDD", "YYYYMM",
  # "YYYY", or "-YYYY..." for BCE. Returns nil for anything not a full positive date.
  def full_date_iso(val)
    return nil if val.nil?
    s = val.to_s.strip
    return nil if s.start_with?('-')  # BCE
    m = s.match(/^(\d{4})(\d{2})(\d{2})$/)
    return nil unless m
    return nil if m[2] == '00' || m[3] == '00'
    "#{m[1]}-#{m[2]}-#{m[3]}"
  end

  # ── notes ──────────────────────────────────────────────────────────────────

  def build_notes
    desc = get('description')
    return [] if desc.nil? || desc.strip.empty?

    [{
      jsonmodel_type: 'note_bioghist',
      label:          'Biographical note',
      subnotes: [{
        jsonmodel_type: 'note_abstract',
        content:        [desc.to_s.strip]
      }]
    }]
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  def parse_date(val)
    parse_wikidata_date(val)
  end

  def get(key)
    vals = @data[key]
    return nil if vals.nil? || vals.empty?
    val = vals.is_a?(Array) ? vals.first : vals
    return nil if val.nil?
    if val.is_a?(Hash)
      val['value'] || val['literal'] || val['content']
    else
      val.to_s
    end
  end

  def get_values(key)
    vals = @data[key]
    return [] if vals.nil?
    arr = vals.is_a?(Array) ? vals : [vals]
    arr.map do |v|
      if v.is_a?(Hash)
        v['value'] || v['literal'] || v['content']
      else
        v.to_s
      end
    end.compact
  end

  def compact_hash(h)
    h.reject { |_k, v| v.nil? || (v.respond_to?(:strip) && v.strip.empty?) }
  end
end
