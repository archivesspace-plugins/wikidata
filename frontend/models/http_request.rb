require 'ashttp'

# Fire a HTTP request with retry logic for flakey REST APIs.
class HTTPRequest

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  RETRIES = 10

  # User-Agent required by Wikidata (https://meta.wikimedia.org/wiki/User-Agent_policy)
  USER_AGENT = 'ArchivesSpace-Wikidata-Plugin/1.0 (https://github.com/archivesspace-plugins/wikidata)'

  def get(uri, headers = {})
    default_headers = { 'User-Agent' => USER_AGENT }
    request_headers = default_headers.merge(headers)

    RETRIES.times do |retry_count|
      if retry_count > 0
        Rails.logger.warn("Retrying GET for #{uri} (attempt #{retry_count} of #{RETRIES})")
      end

      begin
        ASHTTP.start_uri(uri, :open_timeout => OPEN_TIMEOUT, :read_timeout => READ_TIMEOUT) do |http|
          request = Net::HTTP::Get.new(uri)
          request_headers.each { |k, v| request[k] = v }
          response = http.request(request)

          return yield response
        end
      rescue Timeout::Error => e
        Rails.logger.warn("Timeout on request: " + e.to_s)
      end
    end
  end

end
