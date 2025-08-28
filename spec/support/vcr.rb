require 'vcr'
require 'webmock/rspec'

WebMock.disable_net_connect!(net_http_connect_on_start: true, allow_localhost: true)

VCR.configure do |c|
  c.allow_http_connections_when_no_cassette = false
  c.cassette_library_dir = File.join(SpreeAdyen::Engine.root, 'spec', 'vcr')
  c.hook_into :webmock
  c.ignore_localhost = true
  c.configure_rspec_metadata!
  c.default_cassette_options = { record: :once }
  c.filter_sensitive_data('ADYEN_API_KEY') { |i| i.request.headers['X-Api-Key']&.first }
  c.filter_sensitive_data('ADYEN_HMAC_KEY') do |i|
    body = i.response&.body.to_s
    body[/\"hmacKey\":\"([A-F0-9]+)\"/, 1]
  end
  c.filter_sensitive_data('ZmFrZV9zaWduYXR1cmU=') do |i|
    body = i.response&.body.to_s
    # match either normal JSON: "hmacSignature":"<value>"
    # or escaped nested JSON: \"hmacSignature\":\"<value>\"
    body[/"hmacSignature":"(.*?)"/, 1] || body[/\\\"hmacSignature\\\":\\\"(.*?)\\\"/, 1]
  end

  c.filter_sensitive_data('ADYEN_CLIENT_KEY') do |i|
    body = i.response&.body.to_s
    body[/"clientKey":"(.*?)"/, 1] || body[/\\\"clientKey\\\":\\\"(.*?)\\\"/, 1]
  end
  
  c.filter_sensitive_data('ADYEN_USERNAME') do |i|
    body = i.response&.body.to_s
    body[/"username":"(.*?)"/, 1] || body[/\\\"username\\\":\\\"(.*?)\\\"/, 1]
  end
  
  c.filter_sensitive_data('ADYEN_PSP_REFERENCE') do |i|
    body = i.response&.body.to_s
    body[/"pspReference":"(.*?)"/, 1] || body[/\\\"pspReference\\\":\\\"(.*?)\\\"/, 1]
  end

  c.filter_sensitive_data('ADYEN_PAYMENT_PSP_REFERENCE') do |i|
    body = i.response&.body.to_s
    body[/"paymentPspReference":"(.*?)"/, 1] || body[/\\\"paymentPspReference\\\":\\\"(.*?)\\\"/, 1]
  end

  c.before_record do |interaction|
    header_names = %w[X-Stripe-Client-User-Agent]
    headers = header_names.flat_map { |header_name| interaction.request.headers[header_name] }.compact
    %w[Set-Cookie Requestid Pspreference Traceparent].each do |h|
      interaction.response.headers.delete(h)
    end
    interaction.response.body.force_encoding('UTF-8')
    headers.each { |header| interaction.filter!(header, '<FILTERED>') }
  end
end
