module SpreeAdyen
  class WebhookPayloadPresenter
    DEFAULT_PARAMS = {
      active: true,
      communicationFormat: 'json',
      type: 'standard'
    }.freeze

    def initialize(url)
      @url = url
    end

    def to_h
      {
        url: url,
        description: description
      }.merge!(DEFAULT_PARAMS)
    end

    private

    attr_reader :url

    def description
      "Webhook created by SpreeAdyen on #{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S')}"
    end
  end
end
