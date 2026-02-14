# ArchivesSpace Wikidata Plugin

## Overview

The Wikidata plugin is intended to let ArchivesSpace users search [Wikidata](https://www.wikidata.org/) and import selected entities as agents (and optionally subjects). It uses the Wikidata API (`wbsearchentities`, `wbgetentities`) and would convert Wikidata JSON to MARCXML for import via ArchivesSpace’s existing `marcxml_auth_agent` and `marcxml_subjects_and_agents` importers.

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
