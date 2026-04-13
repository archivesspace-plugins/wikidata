# frozen_string_literal: true

require 'capybara/cucumber'
require 'selenium-webdriver'
require 'capybara-screenshot/cucumber'

STAFF_URL = ENV.fetch('STAFF_URL', 'http://localhost:3000')

HEADLESS = ENV.fetch('HEADLESS', '--headless')

SCREENSHOTS_PATH = '/tmp/screenshots'

Capybara.register_driver :firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument(HEADLESS)

  profile = Selenium::WebDriver::Firefox::Profile.new
  profile['webdriver.log.level'] = 'ALL'
  profile['browser.download.dir'] = Dir.tmpdir
  profile['browser.download.folderList'] = 2
  profile['browser.helperApps.alwaysAsk.force'] = false
  options.profile = profile

  Capybara::Selenium::Driver.new(app, browser: :firefox, options:)
end

Capybara.default_driver = :firefox
Capybara.default_max_wait_time = 15

BeforeAll do
  require 'net/http'
  begin
    response = Net::HTTP.get_response(URI(STAFF_URL))
    raise "\nNo server found running on #{STAFF_URL}.\n\n" if response.code != '200'
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET
    raise "\nNo server found running on #{STAFF_URL}.\n\n"
  end
end

Capybara.save_path = SCREENSHOTS_PATH

Capybara::Screenshot.register_driver(:firefox) do |driver, path|
  driver.browser.save_screenshot(path)
end

After do |scenario|
  if scenario.failed?
    uuid = SecureRandom.uuid
    scenario_name = scenario.name.downcase.gsub(' ', '_')

    Capybara::Screenshot.register_filename_prefix_formatter(:firefox) do |_example|
      scenario_name
    end

    timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
    filename = "#{scenario_name}-screenshot-#{timestamp}-#{uuid}.png"
    filepath = File.join(SCREENSHOTS_PATH, filename)
    page.save_screenshot(filepath)
  end
end
