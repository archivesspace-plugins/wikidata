Feature: Wikidata Import
  Background:
    Given an admin is logged in to ArchivesSpace

  Scenario: Import a person from Wikidata and verify data on agent page
    Given the user is on the Wikidata import page
     When the user searches for 'Q937' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
      And the user clicks on 'Import' in the Wikidata panel
     Then the import succeeds and redirects to the agent page
      And the agent name contains 'Einstein'
      And the agent has a birth date of '1879'
      And the agent has a death date of '1955'
      And the agent has no date expression for the birth date

  Scenario: Importing a person that is already in the system redirects to the existing record
    Given the user is on the Wikidata import page
     When the user searches for 'Q42' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
      And the user clicks on 'Import' in the Wikidata panel
     Then the import succeeds and redirects to the agent page
      And the agent name contains 'Adams'
