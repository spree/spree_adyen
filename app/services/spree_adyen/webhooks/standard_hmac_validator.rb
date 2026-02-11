module SpreeAdyen
  module Webhooks
    class StandardHmacValidator
      def initialize(request:, params:, gateway:)
        @request = request
        @params = params
        @gateway = gateway
      end

      def call
        hmac_keys.any? do |hmac_key|
          Adyen::Utils::HmacValidator.new.valid_webhook_hmac?(
            webhook_request_item,
            hmac_key
          )
        end
      end

      private

      attr_reader :request, :params, :gateway

      def hmac_keys
        [
          gateway.preferred_hmac_key,
          gateway.previous_hmac_key
        ].compact
      end

      def webhook_request_item
        params.dig('notificationItems', 0, 'NotificationRequestItem') || {}
      end
    end
  end
end
