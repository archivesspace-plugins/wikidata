Feature: Wikidata Import
  Background:
    Given an admin is logged in to ArchivesSpace

  Scenario: Import a person from Wikidata and verify all fields
    Given the user is on the Wikidata import page
     When the user searches for 'Q937' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
      And the user clicks on 'Import' in the Wikidata panel
     Then the import succeeds and redirects to the agent page
      # A single selected agent lands directly on its edit page
      And the current page is the agent edit page
      # Name verification
      And the agent name contains 'Einstein'
      And the agent has given name 'Albert'
      # Date verification
      And the agent has a birth date of '1879'
      And the agent has a death date of '1955'
      And the agent has no date expression for the birth date
      # Biography/description
      And the agent has a biography containing 'theoretical physicist'
      # Identifiers (external authorities)
      And the agent has a Library of Congress ID 'n79022889'
      And the agent has a VIAF ID '75121530'

  Scenario: Importing a person already in the system redirects and verifies all fields
    Given the user is on the Wikidata import page
     When the user searches for 'Q42' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
      And the user clicks on 'Import' in the Wikidata panel
     Then the import succeeds and redirects to the agent page
      # Name verification (Douglas Adams has two given names: Douglas and Noël)
      And the agent name contains 'Adams'
      And the agent has given name 'Douglas'
      # Alternative name (pseudonym)
      And the agent has alternative name 'Agnew'
      # Date verification
      And the agent has a birth date of '1952'
      And the agent has a death date of '2001'
      # Biography
      And the agent has a biography containing 'science fiction writer'
      # Identifiers
      And the agent has a Library of Congress ID 'n80076765'
      And the agent has a VIAF ID '113230702'

  Scenario: Importing multiple agents shows a summary with links to review or edit each
    Given the user is on the Wikidata import page
     When the user searches for 'Q937' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
     When the user searches for 'Q7186' in Wikidata
     Then Wikidata search results are displayed
     When the user selects the first Wikidata result
      And the user clicks on 'Import' in the Wikidata panel
     Then the import shows a summary of 2 imported agents
      And the summary has a link to review or edit each agent
