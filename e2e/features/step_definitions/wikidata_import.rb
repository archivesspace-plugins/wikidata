# frozen_string_literal: true

# A single import lands on the agent EDIT page, where field values live in
# <input>/<textarea> elements. Their values are not matched by have_text, so
# check page text first, then form-field values.
def agent_page_shows?(str)
  return true if page.has_text?(str, wait: 5)
  return true if page.has_css?("input[value*='#{str}']", visible: :all, wait: 1)
  page.all('textarea', visible: :all).any? { |t| t.value.to_s.include?(str) }
end

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
  # Re-find on each attempt: a fresh search re-renders #results, which can leave a
  # previously-located node stale.
  attempts = 0
  begin
    find('#results .wikidata-result .select-record', match: :first, wait: 10).click
  rescue Selenium::WebDriver::Error::StaleElementReferenceError
    attempts += 1
    retry if attempts < 5
    raise
  end
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

Then 'the current page is the agent edit page' do
  expect(page).to have_current_path(%r{/agents/agent_(person|family|corporate_entity)/\d+/edit}, wait: 15)
end

Then 'the import shows a summary of {int} imported agents' do |count|
  expect(page).to have_text 'Import Complete', wait: 15
  expect(page).to have_text 'review or edit'
  expect(page).to have_css('a[href*="/agents/"]', minimum: count, wait: 5)
end

Then 'the summary has a link to review or edit each agent' do
  links = all('a[href*="/agents/"]')
  expect(links.length).to be >= 2
  links.each { |l| expect(l[:href]).to match(%r{/agents/agent_(person|family|corporate_entity)/\d+/edit}) }
end

When 'the import finishes' do
  # Allow the AJAX post plus the post-import redirect (newly created, ~1.5s)
  # or the modal (already exists) to settle.
  wait_for_ajax
  sleep 3
end

When 'the user re-opens the Wikidata import page' do
  visit "#{STAFF_URL}/plugins/wikidata"
  expect(page).to have_text 'Wikidata Import'
end

Then 'an {string} notice links to the existing record' do |title|
  expect(page).to have_text title, wait: 15
  expect(page).to have_text 'This agent has already been imported'
  expect(page).to have_css('a[href*="/agents/agent_"]')
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
  # "Rest of Name" field on the edit page (or text on the show page).
  expect(agent_page_shows?(given_name)).to be(true), "expected given name #{given_name.inspect} on the page"
end

Then 'the agent has alternative name {string}' do |alt_name|
  # Alternative names (pseudonyms/aliases) appear as additional name-form fields.
  expect(agent_page_shows?(alt_name)).to be(true), "expected alternative name #{alt_name.inspect} on the page"
end

Then 'the agent has a biography containing {string}' do |biography_text|
  # Biography appears in a note section (Biographical note, Historical note, etc.)
  expect(agent_page_shows?(biography_text)).to be(true), "expected biography text #{biography_text.inspect} on the page"
end

Then 'the agent has a Library of Congress ID {string}' do |lc_id|
  # Library of Congress identifier in the record identifiers section.
  expect(agent_page_shows?(lc_id)).to be(true), "expected LC id #{lc_id.inspect} on the page"
end

Then 'the agent has a VIAF ID {string}' do |viaf_id|
  # VIAF identifier in the record identifiers section.
  expect(agent_page_shows?(viaf_id)).to be(true), "expected VIAF id #{viaf_id.inspect} on the page"
end

