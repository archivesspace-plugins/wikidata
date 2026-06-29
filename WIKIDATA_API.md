# Wikidata SPARQL Query API

## Overview

The ArchivesSpace Wikidata plugin uses the [Wikidata SPARQL Query Service](https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service) to fetch entity data for import as agent records. SPARQL is an RDF query language that allows extraction of structured data from Wikidata's knowledge graph.

## API Endpoint

| Purpose | URL |
|---------|-----|
| **SPARQL endpoint** | `https://query.wikidata.org/sparql` |
| **Alternative endpoint** | `https://query.wikidata.org/bigdata/namespace/wdq/sparql` |
| **Web interface** | `https://query.wikidata.org/` |

## Request Format

Queries are submitted via **GET** request with the SPARQL query as a URL-encoded parameter:

```
https://query.wikidata.org/sparql?query={URL_ENCODED_SPARQL}&format=json
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | Yes | The SPARQL query string (URL-encoded) |
| `format` | No | Response format: `json` (default: XML) |

### Response Format

- **JSON**: Add `format=json` to the query string, or send header `Accept: application/sparql-results+json`
- **XML**: Default format
- **CSV/TSV**: Also supported for tabular results

## SPARQL Query Structure

The plugin uses a unified SPARQL query template that fetches all relevant properties for agent import. The query uses `UNION` blocks to retrieve:

- **Name components**: given name (P735), family name (P734), generational suffix (P8017), honorific prefix (P511)
- **Aliases**: pseudonym (P742), alternative labels (skos:altLabel)
- **Dates**: date of birth (P569), date of death (P570), inception (P571), dissolved date (P576), plus each value's time precision (`wikibase:timePrecision`, fetched from the statement value node)
- **Labels**: rdfs:label, schema:description
- **Identifiers**: qNumber, Library of Congress (P244), SNAC (P3430), VIAF (P214)
- **External resources**: Wikidata URL (always), Wikipedia article URL (if available, via `schema:about` + `schema:isPartOf <https://en.wikipedia.org/>`)
- **Type detection**: instance of (P31), isHuman (Q5), isFamily (Q8436), isCorporateBody (corporate body Q106668099 and its subclasses, via `wdt:P31/wdt:P279*`)

The Q number in the query is parameterized (e.g., `wd:Q42` becomes `wd:Q{extracted_id}`) so the same query template works for any Wikidata entity.

## Agent Type Mapping

| Wikidata `instance of` (P31) | ArchivesSpace Agent Type |
|------------------------------|---------------------------|
| human (Q5) | `agent_person` |
| family (Q8436) or subclass | `agent_family` |
| corporate body (Q106668099) or subclass — not family | `agent_corporate_entity` |

Corporate detection follows the full subclass chain (`wdt:P31/wdt:P279* wd:Q106668099`). As a fallback for popular entities whose property-path query may time out, the plugin also matches `instance of` against a curated list of common organizational types (`WikidataResultSet::KNOWN_ORG_TYPES`).

## Property Mappings (Wikidata → ArchivesSpace)

### Person (agent_person)

| Wikidata Property | SPARQL Field Name | ArchivesSpace Field |
|------------------|-------------------|----------------------|
| P735 (given name) | givenName | Name Forms → Rest of Name |
| P734 (family name) | familyName | Name Forms → Primary Part of Name |
| P8017 (generational suffix) | generationalSuffix | Name Forms → Suffix |
| P511 (honorific prefix) | honorificPrefix | Name Forms → Prefix |
| P742 (pseudonym) | pseudonym | Name Forms (alias, authorized: false) |
| skos:altLabel | alias | Name Forms (alias, authorized: false) |
| rdfs:label | label | Name Forms (fallback if no given/family) |
| P569 (date of birth) | dateOfBirth | Dates of Existence → Begin |
| P570 (date of death) | dateOfDeath | Dates of Existence → End |
| schema:description | description | Biography/Historical Note |
| ID | qNumber | Record Identifier (source: wikidata, primary) |
| P244 | libraryOfCongressAuthorityId | Record Identifier (source: Library of Congress) |
| P3430 | snacArkId | Record Identifier (source: snac) |
| P214 | viafClusterId | Record Identifier (source: viaf) |

**Name order**: Use "Indirect" when a family name is present; use "Direct" when using the label only.

**Authorized form**: the entity label is the authoritative full name. The family name (P734) is used only to split the label into Primary Part of Name and Rest of Name. When an entity has several family names (e.g. Imelda Marcos has both *Marcos* and *Romuáldez*), the one the label ends with is used as the Primary Part of Name.

**Identifier sources**: the `wikidata` (primary QID) and `viaf` sources are added to the `name_source` enumeration by the plugin's database migrations; `naf` and `snac` are part of the ArchivesSpace defaults.

### Family (agent_family)

| Wikidata Property | SPARQL Field Name | ArchivesSpace Field |
|------------------|-------------------|----------------------|
| rdfs:label | label | Name Forms → Family Name |
| P742 (pseudonym) | pseudonym | Name Forms (alias) |
| skos:altLabel | alias | Name Forms (alias) |
| schema:description | description | Biography/Historical Note |
| P569, P570, P571, P576 | dates | Dates of Existence |
| Identifiers | same as person | Record Identifiers |

### Corporate (agent_corporate_entity)

| Wikidata Property | SPARQL Field Name | ArchivesSpace Field |
|------------------|-------------------|----------------------|
| rdfs:label | label | Name Forms → Primary Part of Name |
| P742 (pseudonym) | pseudonym | Name Forms (alias) |
| skos:altLabel | alias | Name Forms (alias) |
| P571 (inception) | inception | Dates of Existence → Begin |
| P576 (dissolved) | dissolvedDate | Dates of Existence → End |
| schema:description | description | Biography/Historical Note |
| Identifiers | same as person | Record Identifiers |

## User Input

Users provide a Wikidata URL or Q ID:

- **URL**: `https://www.wikidata.org/wiki/Q42`
- **Q ID**: `Q42` (extracted from URL or entered directly)

The plugin extracts the Q number (e.g., `Q42`) and substitutes it into the SPARQL query.

## External Documents

When importing an agent, the plugin automatically creates related external resource links:

| Resource | URL | Always present? |
|----------|-----|-----------------|
| **Wikidata** | `https://www.wikidata.org/wiki/{Q_ID}` | Yes |
| **Wikipedia** | `https://en.wikipedia.org/wiki/...` | Only if the Wikidata entity links to a Wikipedia article |

These appear in ArchivesSpace as "Related External Resources" on the agent record view.

## Date Handling

Wikidata dates carry a precision (`wikibase:timePrecision`: 9 = year, 10 = month, 11 = day). See [Wikidata Help:Dates](https://www.wikidata.org/wiki/Help:Dates) and [Help:Dates#Precision](https://www.wikidata.org/wiki/Help:Dates#Precision).

The truthy `wdt:` predicate normalizes year- and month-precision dates to `YYYY-01-01`, so the plugin fetches the precision and standardizes each date at the granularity Wikidata actually knows — rather than emitting an over-precise full date.

| Date precision | ArchivesSpace field | Example |
|----------------|---------------------|---------|
| Day (precision 11) | `date_standardized` | `1879-03-14` |
| Month (precision 10) | `date_standardized` | `1960-06` |
| Year (precision 9, or coarser) | `date_standardized` | `1961` |
| BCE / negative year | `date_expression` | `550 BCE` |
| Unparseable | `date_expression` | `19th Century` |

The two fields are **never set simultaneously** for the same date endpoint. This avoids the double-display issue present in the MARCXML importer (see [Workarounds](#workarounds) in README).

## References

- [Wikidata:SPARQL query service](https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service)
- [Wikidata Query Service User Manual](https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual)
- [SPARQL 1.1 W3C Recommendation](https://www.w3.org/TR/sparql11-overview/)
- [Wikidata Help:Dates](https://www.wikidata.org/wiki/Help:Dates)
