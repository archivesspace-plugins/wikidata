# ArchivesSpace Wikidata Plugin

> [!CAUTION]
> This is work in progress!
> 
> This is the first working version of the plugin, ready to be tested.



## Overview

The Wikidata plugin lets ArchivesSpace users import [Wikidata](https://www.wikidata.org/) entities as agent records. Users provide a Wikidata URL (e.g. `https://www.wikidata.org/wiki/Q42`) or Q ID, and the plugin fetches entity data via the [Wikidata SPARQL Query API](https://query.wikidata.org/) and creates agent records directly through the ArchivesSpace JSONModel API.

Supported agent types: **Person** (Q5), **Family** (Q8436), **Corporate** (Q131085629 and subclasses).

Imported records include:
- Names (given name, family name, pseudonyms, aliases)
- Birth/death dates (or inception/dissolved for organizations)
- Biography/description
- External authority identifiers (Library of Congress, VIAF, SNAC)
- Related external resources (Wikidata URL + Wikipedia article link, if available)

See [WIKIDATA_API.md](WIKIDATA_API.md) for API documentation and field mappings.

## Installation

1. Add the plugin as a submodule (or clone into `plugins/wikidata`):
   ```bash
   git submodule add https://github.com/archivesspace-plugins/wikidata plugins/wikidata
   ```

2. Enable it in `config/config.rb`:
   ```ruby
   AppConfig[:plugins] = ['local', 'lcnaf', 'wikidata']
   ```

3. Restart ArchivesSpace.

## Testing

### Unit tests

Unit tests run with Minitest and do not require a running ArchivesSpace instance. From the plugin root:

```bash
cd frontend/spec
for f in *_spec.rb; do ruby "$f"; done
```

Or run a single spec file:

```bash
cd frontend/spec
ruby wikidata_to_marcxml_spec.rb
```

### End-to-end tests

E2e tests use Cucumber + Capybara with a headless Firefox browser. They require a running ArchivesSpace instance (backend + frontend).

**Prerequisites:** Ruby 3.x, Firefox, [geckodriver](https://github.com/mozilla/geckodriver) (`brew install geckodriver` on macOS).

```bash
cd e2e
bundle install
bundle exec cucumber
```

By default, tests connect to `http://localhost:3000`. Override with:

```bash
STAFF_URL=http://localhost:8080 bundle exec cucumber
```

To run with a visible browser (non-headless):

```bash
HEADLESS= bundle exec cucumber
```

## Workarounds

### Direct JSON agent creation instead of MARCXML import

The ArchivesSpace MARCXML auth agent importer (`marcxml_auth_agent`) reads each MARC 046 subfield twice: once through `structured_date_for` (which attempts `DateTime.parse` for `date_standardized`) and once through `expression_date_for` (which copies the raw text into `date_expression`). Both fields are always set on the resulting structured date object (see `marcxml_auth_agent_base_map.rb`, lines 594-636). This causes dates to display twice on the agent page — for example, `1879-03-14` appears as both the standardized date and the expression.

To avoid this, the plugin bypasses the MARCXML importer and creates agents directly via the JSONModel API (`WikidataToAgent`). This allows precise control: full-precision dates (YYYY-MM-DD) are stored only as `date_standardized`, while year-only, BCE, and unparseable dates are stored only as `date_expression`.

The original MARCXML converter (`WikidataToMarcxml`) is retained for agent type detection logic.

### Duplicate detection with Solr indexing lag

When importing an agent, the plugin first searches Solr for an existing agent with the same `authority_id` (Wikidata QID). If found, it redirects to the existing record.

However, Solr indexing can lag behind the database. A freshly created agent may not appear in search results immediately. To handle this, the plugin also catches the `JSONModel::ValidationException` raised by the ArchivesSpace backend when a uniqueness constraint is violated, and extracts the conflicting record URI from the exception to redirect to the existing agent.

## Version compatibility

Compatibility follows the main ArchivesSpace release. Check the [ArchivesSpace tech docs](https://docs.archivesspace.org/) for supported versions.
