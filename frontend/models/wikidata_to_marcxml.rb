# Converts Wikidata SPARQL results (hash of propertyName => values) to MARCXML
# for import via marcxml_auth_agent. Handles person, family, and corporate entity types.
require 'rexml/document'
require 'cgi'

class WikidataToMarcxml
  SOURCE_MAP = {
    'libraryOfCongressAuthorityId' => 'Library of Congress Name Authority File',
    'snacArkId' => 'SNAC',
    'viafClusterId' => 'viaf'
  }.freeze

  def initialize(data, qid)
    @data = data
    @qid = qid.to_s.upcase
    @qid = "Q#{@qid}" unless @qid.start_with?('Q')
  end

  def to_marcxml
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new('1.0', 'UTF-8')
    record = doc.add_element('record', 'xmlns' => 'http://www.loc.gov/MARC21/slim')

    add_leader(record)
    add_controlfield(record, '001', @qid)
    add_identifiers(record)
    add_dates(record)
    add_bioghist(record)
    add_name_fields(record)

    doc.to_s
  end

  # Known Wikidata types that are subclasses of Q131085629 (collective agent).
  KNOWN_ORG_TYPES = WikidataResultSet::KNOWN_ORG_TYPES

  def agent_type
    return 'agent_family' if get_value('isFamily') == 'true'
    return 'agent_person' if get_value('isHuman') == 'true'
    # Fallback: check instanceQid against known org types (handles SPARQL timeout)
    instance_qids = get_values('instanceQid')
    if instance_qids.any? { |qid| KNOWN_ORG_TYPES.include?(qid) }
      return 'agent_family' if instance_qids.include?('Q8436')
      return 'agent_corporate_entity'
    end
    # Legacy fallback for older SPARQL responses
    return 'agent_corporate_entity' if get_value('isCollectiveAgent') == 'true'
    'agent_person' # default
  end

  private

  def get_value(key)
    vals = @data[key]
    return nil if vals.nil? || vals.empty?
    val = vals.is_a?(Array) ? vals.first : vals
    return nil if val.nil?
    # SPARQL returns typed values; extract string from "value" or "literal"
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

  def add_leader(record)
    leader = record.add_element('leader')
    # Position 6: type of record (z=authority), 7: bib level (a=monograph)
    leader.text = '00000nz  a22^^^^^n^a4500'
  end

  def add_controlfield(record, tag, value)
    cf = record.add_element('controlfield', 'tag' => tag)
    cf.text = value.to_s
  end

  def add_identifiers(record)
    # Wikidata Q number as primary (024 ind1=7, subfield 2=wikidata)
    add_datafield(record, '024', '7', ' ', ['a', @qid], ['2', 'wikidata'], ['1', "https://www.wikidata.org/wiki/#{@qid}"])

    # LCN (P244)
    add_identifier_if_present(record, 'libraryOfCongressAuthorityId', 'Library of Congress Name Authority File')
    # SNAC (P3430)
    add_identifier_if_present(record, 'snacArkId', 'SNAC')
    # VIAF (P214)
    add_identifier_if_present(record, 'viafClusterId', 'viaf')
  end

  def add_identifier_if_present(record, key, source)
    val = get_value(key)
    return if val.nil? || val.to_s.strip.empty?
    add_datafield(record, '024', '7', ' ', ['a', val.to_s], ['2', source])
  end

  def add_dates(record)
    case agent_type
    when 'agent_person'
      add_person_dates(record)
    when 'agent_family'
      add_family_dates(record)
    when 'agent_corporate_entity'
      add_corporate_dates(record)
    end
  end

  def add_person_dates(record)
    begin_date = parse_wikidata_date(get_value('dateOfBirth'))
    end_date = parse_wikidata_date(get_value('dateOfDeath'))
    add_046(record, begin_date, end_date)
  end

  def add_family_dates(record)
    begin_date = parse_wikidata_date(get_value('dateOfBirth')) || parse_wikidata_date(get_value('inception'))
    end_date = parse_wikidata_date(get_value('dateOfDeath')) || parse_wikidata_date(get_value('dissolvedDate'))
    add_046(record, begin_date, end_date)
  end

  def add_corporate_dates(record)
    begin_date = parse_wikidata_date(get_value('inception'))
    end_date = parse_wikidata_date(get_value('dissolvedDate'))
    add_046(record, begin_date, end_date)
  end

  def parse_wikidata_date(val)
    return nil if val.nil? || val.to_s.strip.empty?
    s = val.to_s.strip
    # Wikidata dates: "+1952-03-11T00:00:00Z", "-0550-01-01T00:00:00Z" (BCE), "1952"
    # Preserve precision: year-only → "1960", year-month → "196006", full → "19520311"
    # BCE dates: "-0550" → "-0550"
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

  def add_046(record, begin_date, end_date)
    return if begin_date.nil? && end_date.nil?
    subfields = []
    subfields << ['f', begin_date] if begin_date
    subfields << ['g', end_date] if end_date
    return if subfields.empty?
    add_datafield(record, '046', ' ', ' ', *subfields)
  end

  def add_bioghist(record)
    desc = get_value('description')
    return if desc.nil? || desc.to_s.strip.empty?
    add_datafield(record, '678', '0', ' ', ['a', desc.to_s])
  end

  def add_name_fields(record)
    case agent_type
    when 'agent_person'
      add_person_names(record)
    when 'agent_family'
      add_family_names(record)
    when 'agent_corporate_entity'
      add_corporate_names(record)
    end
  end

  def add_person_names(record)
    given = get_value('givenName')
    family = get_value('familyName')
    label = get_value('label')
    prefix = get_value('honorificPrefix')
    suffix = get_value('generationalSuffix')

    if family || given
      # Indirect/inverted: "Family, Given"
      primary = [family, given].compact.join(', ')
      primary = label if primary.strip.empty?
      ind1 = '1' # inverted
    else
      primary = label || @qid
      ind1 = '0' # direct
    end

    subfields = []
    subfields << ['a', primary] if primary
    subfields << ['c', prefix] if prefix && !prefix.to_s.strip.empty?
    subfields << ['b', suffix] if suffix && !suffix.to_s.strip.empty?

    add_datafield(record, '100', ind1, ' ', *subfields) if primary

    # Aliases and pseudonyms as 400 (additional name forms, direct order)
    all_aliases = get_values('alias') + get_values('pseudonym')
    all_aliases.uniq.each do |alias_name|
      add_datafield(record, '400', '0', ' ', ['a', alias_name])
    end
  end

  def add_family_names(record)
    label = get_value('label')
    primary = label || @qid
    add_datafield(record, '100', '3', ' ', ['a', primary]) if primary

    all_aliases = get_values('alias') + get_values('pseudonym')
    all_aliases.uniq.each do |alias_name|
      add_datafield(record, '400', '3', ' ', ['a', alias_name])
    end
  end

  def add_corporate_names(record)
    label = get_value('label')
    primary = label || @qid
    add_datafield(record, '110', '2', ' ', ['a', primary]) if primary

    all_aliases = get_values('alias') + get_values('pseudonym')
    all_aliases.uniq.each do |alias_name|
      add_datafield(record, '410', '2', ' ', ['a', alias_name])
    end
  end

  def add_datafield(record, tag, ind1, ind2, *subfields)
    df = record.add_element('datafield', 'tag' => tag, 'ind1' => ind1, 'ind2' => ind2)
    subfields.each do |code, value|
      next if value.nil? || value.to_s.strip.empty?
      sf = df.add_element('subfield', 'code' => code)
      sf.text = escape_xml(value.to_s)
    end
  end

  def escape_xml(str)
    CGI.escapeHTML(str.to_s)
  end
end
