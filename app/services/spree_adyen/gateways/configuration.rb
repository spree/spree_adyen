module SpreeAdyen
  module Gateways
    class Configuration
      def initialize(response_body)
        @response_body = response_body
      end

      def client_key
        response_body['clientKey']
      end

      def roles
        response_body['roles']
      end

      def active?
        response_body['active'].to_s == 'true'
      end

      def allowed_origins
        response_body['allowedOrigins'].map { |origin| origin['domain'] }
      end

      def merchant_account
        response_body['associatedMerchantAccounts'].first
      end

      def id
        response_body['id']
      end

      def company
        response_body['companyName']
      end

      private

      attr_reader :response_body
    end
  end
end
