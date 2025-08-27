module SpreeAdyen
  module Gateways
    class AddAllowedOrigin
      ALREADY_EXISTS_ERROR_CODE = '31_004'.freeze

      def initialize(record, gateway)
        @record = record
        @gateway = gateway
      end

      def call
        response = gateway.add_allowed_origin(allowed_origin)

        if response.success?
          log("added to gateway #{gateway.id}")
        elsif response.message['errorCode'] == ALREADY_EXISTS_ERROR_CODE
          log('already exists', :warn)
        else
          Rails.error.unexpected('Cannot create allowed origin', context: { url: allowed_origin, gateway_id: gateway.id }, source: 'spree_adyen')
        end
      end

      private

      attr_reader :record, :gateway

      def log(message, level = :info)
        Rails.logger.send(level, "[SpreeAdyen][AddAllowedOrigin]: Origin #{allowed_origin} #{message}")
      end

      def allowed_origin
        @allowed_origin ||= URI::HTTPS.build(host: record.url).to_s
      end
    end
  end
end
