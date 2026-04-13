# frozen_string_literal: true

def login_admin
  visit "#{STAFF_URL}/logout"

  page.has_xpath? '//input[@id="login"]'

  within 'form.login' do
    fill_in 'username', with: 'admin'
    fill_in 'password', with: 'admin'
    click_on 'Sign In'
  end

  wait_for_ajax

  expect(page).not_to have_content('Please Sign In')
  expect(page).to have_content 'Welcome to ArchivesSpace'
  element = find('.global-header .user-container')
  expect(element.text.strip).to eq 'admin'
end

def wait_for_ajax
  Timeout.timeout(Capybara.default_max_wait_time) do
    javascript_error_tries = 0

    begin
      sleep 1 until page.evaluate_script('jQuery.active')&.zero?
    rescue Selenium::WebDriver::Error::JavascriptError => e
      raise e if javascript_error_tries == 5

      javascript_error_tries += 1
      sleep 3
      retry
    end
  end
end
