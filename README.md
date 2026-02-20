> [!WARNING]
> This is work in progress there is no functioning version of this plugin available yet. This warning will be removed as soon as there is a first version that can be tested available.


# ArchivesSpace Wikidata Plugin

## Overview

The Wikidata plugin lets ArchivesSpace users import [Wikidata](https://www.wikidata.org/) entities as agent records. Users provide a Wikidata URL (e.g. `https://www.wikidata.org/wiki/Q42`) or Q ID, and the plugin fetches entity data via the [Wikidata SPARQL Query API](https://query.wikidata.org/) and converts it to MARCXML for import via ArchivesSpace's `marcxml_auth_agent` importer.

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

## Version compatibility

Compatibility follows the main ArchivesSpace release. Check the [ArchivesSpace tech docs](https://docs.archivesspace.org/) for supported versions.
