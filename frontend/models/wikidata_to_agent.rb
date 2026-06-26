# Converts a Wikidata SPARQL result set into an ArchivesSpace agent JSON hash
# suitable for direct API creation via JSONModel.
#
# Dates: standardized at whatever granularity Wikidata reports via its time
# precision (YYYY, YYYY-MM, or YYYY-MM-DD). BCE and unparseable values are
# stored as date_expression instead. A field never carries both.

require_relative 'wikidata_date_parser'
require_relative 'wikidata_result_set'

class WikidataToAgent
  include WikidataDateParser

  KNOWN_ORG_TYPES = WikidataResultSet::KNOWN_ORG_TYPES

  # name_source enum value attributing imported records to Wikidata.
  # Seeded by plugins/wikidata/migrations/001_add_wikidata_name_source.rb.
  WIKIDATA_SOURCE = 'wikidata'.freeze

  # Maps Wikidata field names to valid ArchivesSpace agent_record_identifiers/source enum values.
  # ArchivesSpace accepts: local, nad, naf, ulan, ingest, snac
  AGENT_SOURCE_MAP = {
    'libraryOfCongressAuthorityId' => 'naf',   # Library of Congress Name Authority File
    'snacArkId'                    => 'snac',  # Social Networks and Archival Context
    'viafClusterId'                => 'local'  # VIAF has no dedicated ArchivesSpace enum; store as local
  }.freeze

  def initialize(data, qid)
    @data = data
    @qid  = qid.to_s.upcase
    @qid  = "Q#{@qid}" unless @qid.start_with?('Q')
  end

  def agent_type
    @agent_type ||= begin
      return 'agent_family' if get('isFamily') == 'true'
      return 'agent_person' if get('isHuman') == 'true'
      return 'agent_corporate_entity' if get('isCorporateBody') == 'true'
      instance_qids = get_values('instanceQid')
      if instance_qids.any? { |q| KNOWN_ORG_TYPES.include?(q) }
        return 'agent_family' if instance_qids.include?('Q8436')
        return 'agent_corporate_entity'
      end
      return 'agent_corporate_entity' if get('isCollectiveAgent') == 'true'
      'agent_person'
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

    primary, rest, order, sort_key = derive_person_name(label, family, given)

    name = compact_hash(
      jsonmodel_type: 'name_person',
      primary_name:   primary,
      rest_of_name:   rest,
      prefix:         prefix,
      suffix:         suffix,
      name_order:     order,
      source:         WIKIDATA_SOURCE,
      rules:          'local',
      sort_name:      sort_key,
      authority_id:   @qid
    )

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_person', primary_name: a,
        name_order: 'direct', source: WIKIDATA_SOURCE, rules: 'local', sort_name: a }
    end

    {
      jsonmodel_type:           'agent_person',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(parse_date(get('dateOfBirth'), get('dateOfBirthPrecision')),
                                             parse_date(get('dateOfDeath'), get('dateOfDeathPrecision'))),
      notes:                    build_notes,
      external_documents:       build_external_documents
    }
  end

  def build_family
    label = get('label') || @qid
    name  = { jsonmodel_type: 'name_family', family_name: label,
               source: WIKIDATA_SOURCE, rules: 'local', sort_name: label,
               authority_id: @qid }

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_family', family_name: a,
        source: WIKIDATA_SOURCE, rules: 'local', sort_name: a }
    end

    begin_date = parse_date(get('dateOfBirth'), get('dateOfBirthPrecision')) ||
                 parse_date(get('inception'), get('inceptionPrecision'))
    end_date   = parse_date(get('dateOfDeath'), get('dateOfDeathPrecision')) ||
                 parse_date(get('dissolvedDate'), get('dissolvedDatePrecision'))

    {
      jsonmodel_type:           'agent_family',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(begin_date, end_date),
      notes:                    build_notes,
      external_documents:       build_external_documents
    }
  end

  def build_corporate
    label = get('label') || @qid
    name  = { jsonmodel_type: 'name_corporate_entity', primary_name: label,
               source: WIKIDATA_SOURCE, rules: 'local', sort_name: label,
               authority_id: @qid }

    aliases = (get_values('alias') + get_values('pseudonym')).uniq.map do |a|
      { jsonmodel_type: 'name_corporate_entity', primary_name: a,
        source: WIKIDATA_SOURCE, rules: 'local', sort_name: a }
    end

    {
      jsonmodel_type:           'agent_corporate_entity',
      agent_record_identifiers: build_identifiers,
      names:                    [name] + aliases,
      dates_of_existence:       build_dates(parse_date(get('inception'), get('inceptionPrecision')),
                                             parse_date(get('dissolvedDate'), get('dissolvedDatePrecision'))),
      notes:                    build_notes,
      external_documents:       build_external_documents
    }
  end

  # ── identifiers ──────────────────────────────────────────────────────────

  def build_identifiers
    ids = [{
      primary_identifier: true,
      record_identifier:  @qid,
      source:             WIKIDATA_SOURCE,
      identifier_type:    'local'
    }]

    AGENT_SOURCE_MAP.each do |field, source_name|
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
  # Rule: use date_standardized at the precision Wikidata reports (YYYY,
  # YYYY-MM, or YYYY-MM-DD). Use date_expression for BCE or unparseable values.
  # Never set both for the same date field.

  def build_dates(begin_val, end_val)
    return [] if begin_val.nil? && end_val.nil?

    begin_std  = standardized_iso(begin_val)
    end_std    = standardized_iso(end_val)

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
               date_expression: format_date_for_display(val) }
           end
    else
      sd = { jsonmodel_type: 'structured_date_range' }

      if begin_std
        sd[:begin_date_standardized]      = begin_std
        sd[:begin_date_standardized_type] = 'standard'
      elsif begin_val
        sd[:begin_date_expression] = format_date_for_display(begin_val)
      end

      if end_std
        sd[:end_date_standardized]      = end_std
        sd[:end_date_standardized_type] = 'standard'
      elsif end_val
        sd[:end_date_expression] = format_date_for_display(end_val)
      end
    end

    [{
      jsonmodel_type:               'structured_date_label',
      date_label:                   'existence',
      date_type_structured:         date_type,
      "structured_date_#{date_type}" => sd
    }]
  end

  # Returns an ArchivesSpace-standardisable date string at whatever precision the
  # value carries: "YYYY-MM-DD", "YYYY-MM", or "YYYY". Input is the output of
  # parse_date/parse_wikidata_date: "YYYYMMDD", "YYYYMM", "YYYY", or "-YYYY..."
  # for BCE. Returns nil for BCE or anything not a positive year/month/day value
  # (those fall back to date_expression).
  def standardized_iso(val)
    return nil if val.nil?
    s = val.to_s.strip
    return nil if s.empty? || s.start_with?('-')  # blank or BCE
    if (m = s.match(/^(\d{4})(\d{2})(\d{2})$/))
      return nil if m[2] == '00' || m[3] == '00'
      "#{m[1]}-#{m[2]}-#{m[3]}"
    elsif (m = s.match(/^(\d{4})(\d{2})$/))
      return nil if m[2] == '00'
      "#{m[1]}-#{m[2]}"
    elsif s.match?(/^\d{4}$/)
      s
    end
  end

  # ── external documents ─────────────────────────────────────────────────────

  def build_external_documents
    docs = []

    # Always add Wikidata URL
    docs << {
      jsonmodel_type: 'external_document',
      title:          'Wikidata',
      location:       "https://www.wikidata.org/wiki/#{@qid}",
      publish:        true
    }

    # Add Wikipedia URL if available
    wiki_url = get('wikipediaUrl')
    if wiki_url && !wiki_url.strip.empty?
      docs << {
        jsonmodel_type: 'external_document',
        title:          'Wikipedia',
        location:       wiki_url.strip,
        publish:        true
      }
    end

    docs
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

  # ── name derivation ─────────────────────────────────────────────────────
  # Prefer the item label as the authoritative full name, rendered in indirect
  # (family, given) order. The family name (P734) is used only to split the
  # label — never to pick among multiple given-name (P735) values, which is
  # unreliable when several given names with series ordinals exist.
  #
  # Returns [primary_name, rest_of_name, name_order, sort_name].
  def derive_person_name(label, family, given)
    label  = label.to_s.strip
    family = family.to_s.strip
    given  = given.to_s.strip

    if !family.empty? && !label.empty? && label.downcase.end_with?(family.downcase)
      # Split the label: everything before the trailing family name is the rest.
      rest = label[0...(label.length - family.length)].sub(/[,\s]+\z/, '').strip
      rest = nil if rest.empty?
      [family, rest, 'inverted', [family, rest].compact.join(', ')]
    elsif !family.empty?
      # Family name known but not derivable from the label (e.g. the label is a
      # mononym or pseudonym). Fall back to the given-name triple for the rest.
      rest = given.empty? ? nil : given
      [family, rest, 'inverted', [family, rest].compact.join(', ')]
    else
      # No family name: use the label as-is, in direct order.
      primary = label.empty? ? @qid : label
      [primary, nil, 'direct', primary]
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  def parse_date(val, precision = nil)
    parse_wikidata_date(val, precision)
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
