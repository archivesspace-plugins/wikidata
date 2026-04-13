# frozen_string_literal: true

Given 'an admin is logged in to ArchivesSpace' do
  login_admin
end

Given 'the user is on the Wikidata import page' do
  visit "#{STAFF_URL}/plugins/wikidata"
  expect(page).to have_text 'Wikidata Import'
end

When 'the user searches for {string} in Wikidata' do |query|
  fill_in 'wikidata-search-query', with: query
  click_on 'Search'
  expect(page).to have_css('#results .wikidata-result', wait: 30)
end

Then 'Wikidata search results are displayed' do
  expect(page).to have_css('#results .wikidata-result')
end

When 'the user selects the first Wikidata result' do
  first('#results .wikidata-result').find('.select-record').click
  expect(page).to have_css('#selected [data-qid]')
end

When 'the user clicks on {string} in the Wikidata panel' do |label|
  within '#wikidata_import' do
    click_on label
  end
end

Then 'the import succeeds and redirects to the agent page' do
  # Modal shows success, then JS redirects directly to the agent record
  expect(page).to have_text 'Imported successfully', wait: 15
  # Wait for URL to change to agent page (JS redirects after 1.5s)
  expect(page).to have_current_path(%r{/agents/agent_(person|family|corporate_entity)/\d+}, wait: 15)
end

Then 'the agent name contains {string}' do |name_part|
  expect(page).to have_text name_part
end

Then 'the agent has a birth date of {string}' do |year|
  expect(page).to have_text year
end

Then 'the agent has a death date of {string}' do |year|
  expect(page).to have_text year
end

Then 'the agent has no date expression for the birth date' do
  # The standardized date is used, so no raw numeric expression like "18790314"
  expect(page).not_to have_text '18790314'
  expect(page).not_to have_text '1879-03-14 (expression)'
end

Then 'the agent has given name {string}' do |given_name|
  # Given name appears in the name form details, typically in a "Rest of Name" or similar field
  expect(page).to have_text given_name, wait: 5
end

Then 'the agent has alternative name {string}' do |alt_name|
  # Alternative names (pseudonyms/aliases) appear as separate name forms on the agent page
  expect(page).to have_text alt_name, wait: 5
end

Then 'the agent has a biography containing {string}' do |biography_text|
  # Biography appears in a note section (Biographical note, Historical note, etc.)
  expect(page).to have_text biography_text, wait: 5
end

Then 'the agent has a Library of Congress ID {string}' do |lc_id|
  # Library of Congress identifiers appear in the record identifiers section.
  # The page may only show the identifier value rather than a full source label.
  expect(page).to have_text(lc_id, wait: 5)
end

Then 'the agent has a VIAF ID {string}' do |viaf_id|
  # VIAF identifiers appear in the record identifiers section.
  expect(page).to have_text(viaf_id, wait: 5)
end

