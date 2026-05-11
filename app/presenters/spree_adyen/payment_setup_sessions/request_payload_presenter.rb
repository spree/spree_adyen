module SpreeAdyen
  module PaymentSetupSessions
    # Builds the payload for a zero-auth (tokenization-only) Adyen Sessions API request.
    # Used to vault a payment method without charging the customer — Adyen returns an
    # AUTHORISATION webhook with the stored payment method ID in additionalData.
    class RequestPayloadPresenter
      DEFAULT_PARAMS = {
        recurringProcessingModel: 'UnscheduledCardOnFile',
        shopperInteraction: 'Ecommerce',
        storePaymentMethodMode: 'enabled'
      }.freeze

      DEFAULT_CURRENCY = 'USD'.freeze

      def initialize(customer:, merchant_account:, payment_method:, channel:, return_url:, currency: nil)
        @customer = customer
        @merchant_account = merchant_account
        @payment_method = payment_method
        @channel = channel
        @return_url = return_url
        @currency = currency || DEFAULT_CURRENCY
      end

      def to_h
        {
          metadata: {
            spree_payment_method_id: payment_method.id,
            spree_setup_session: true
          },
          amount: {
            value: 0,
            currency: currency
          },
          returnUrl: return_url,
          reference: reference,
          merchantAccount: merchant_account,
          expiresAt: expires_at
        }.merge!(shopper_details, DEFAULT_PARAMS, channel_params, SpreeAdyen::ApplicationInfoPresenter.new.to_h)
      end

      private

      attr_reader :customer, :merchant_account, :payment_method, :channel, :return_url, :currency

      # Format: SETUP_<payment_method_id>_<unique_guard>
      # Mirrors the order-tied reference convention used in PaymentSessions::RequestPayloadPresenter,
      # but uses a SETUP prefix because there is no order to anchor against.
      def reference
        ['SETUP', payment_method.id, SecureRandom.hex(6)].join('_')
      end

      def channel_params
        case channel
        when 'iOS'
          { blockedPaymentMethods: ['googlepay'], channel: 'iOS' }
        when 'Android'
          { blockedPaymentMethods: ['applepay'], channel: 'Android' }
        when 'Web'
          { channel: 'Web' }
        else
          {}
        end
      end

      def shopper_details
        {
          shopperName: {
            firstName: customer.first_name,
            lastName: customer.last_name
          }.compact,
          shopperEmail: customer.email,
          shopperReference: "customer_#{customer.id}"
        }
      end

      def expires_at
        SpreeAdyen::Config.payment_session_expiration_in_minutes.minutes.from_now.iso8601
      end
    end
  end
end
