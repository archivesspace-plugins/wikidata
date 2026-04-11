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

Then 'the already imported modal is displayed' do
  expect(page).to have_text 'Already Imported', wait: 15
  expect(page).to have_text 'already been imported'
end

Then 'the modal contains a link to the existing agent' do
  within '.modal-content' do
    expect(page).to have_css('a[href*="/agents/"]')
  end
end
