# ArchivesSpace Wikidata Plugin

> [!CAUTION]
> This is work in progress!
> 
> There is no functioning version of this plugin available yet.
> 
> This warning will be removed as soon as there is a first version that can be tested available.



## Overview

The Wikidata plugin lets ArchivesSpace users import [Wikidata](https://www.wikidata.org/) entities as agent records. Users provide a Wikidata URL (e.g. `https://www.wikidata.org/wiki/Q42`) or Q ID, and the plugin fetches entity data via the [Wikidata SPARQL Query API](https://query.wikidata.org/) and creates agent records directly through the ArchivesSpace JSONModel API.

Supported agent types: **Person** (Q5), **Family** (Q8436), **Corporate** (Q131085629 and subclasses). See [WIKIDATA_API.md](WIKIDATA_API.md) for API documentation and field mappings.

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

The ArchivesSpace MARCXML auth agent importer (`marcxml_auth_agent`) always populates **both** `date_standardized` and `date_expression` from the same MARC 046 subfield. This causes dates to display twice on the agent page (e.g. `1879-03-14` as the standardized date and `18790314` as the expression).

To avoid this, the plugin bypasses the MARCXML importer and creates agents directly via the JSONModel API (`WikidataToAgent`). This allows precise control: full-precision dates (YYYY-MM-DD) are stored only as `date_standardized`, while year-only, BCE, and unparseable dates are stored only as `date_expression`.

The original MARCXML converter (`WikidataToMarcxml`) is retained for agent type detection logic.

### Duplicate detection with Solr indexing lag

When importing an agent, the plugin first searches Solr for an existing agent with the same `authority_id` (Wikidata QID). If found, it redirects to the existing record.

However, Solr indexing can lag behind the database. A freshly created agent may not appear in search results immediately. To handle this, the plugin also catches the `JSONModel::ValidationException` raised by the ArchivesSpace backend when a uniqueness constraint is violated, and extracts the conflicting record URI from the exception to redirect to the existing agent.

## Version compatibility

Compatibility follows the main ArchivesSpace release. Check the [ArchivesSpace tech docs](https://docs.archivesspace.org/) for supported versions.
