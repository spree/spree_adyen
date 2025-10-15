module SpreeAdyen
  module Payments
    class RequestPayloadPresenter
      DEFAULT_PARAMS = {
        recurringProcessingModel: 'UnscheduledCardOnFile',
        shopperInteraction: 'ContAuth'
      }.freeze

      def initialize(source:, amount_in_cents:, gateway_options:)
        @source = source
        @amount_in_cents = amount_in_cents
        @gateway_options = gateway_options.with_indifferent_access
      end

      def to_h
        {
          metadata: { # unfortunately metadata is not always available in webhooks, even for AUTHORISATION events
            spree_payment_method_id: source.payment_method_id,
            spree_order_id: order_number
          },
          amount: {
            value: amount_in_cents,
            currency: currency
          },
          paymentMethod: {
            type: 'scheme',
            storedPaymentMethodId: source.gateway_payment_profile_id
          },
          reference: reference,
          shopperReference: shopper_reference,
          merchantAccount: source.payment_method.preferred_merchant_account
        }.merge!(DEFAULT_PARAMS, SpreeAdyen::ApplicationInfoPresenter.new.to_h)
      end

      private

      attr_reader :source, :amount_in_cents, :gateway_options

      delegate :currency, to: :order
      delegate :user, to: :order, allow_nil: true

      # since we cannot count on metadata reference is the simplest way to store data for webhooks
      # so let's keep its format as ORDERNUMBER_PAYMENTMETHODID_UNIQGUARANTER
      def reference
        [
          order_number,
          source.payment_method_id,
          payment_number
        ].join('_')
      end

      # we need to send reference even for guest users, otherwise we can't tokenize the card
      def shopper_reference
        if user.present?
          "customer_#{user.id}"
        else
          "guest_#{order_number}"
        end
      end

      def order_number
        @order_number ||= gateway_options[:order_id].split('-').first
      end

      def payment_number
        @payment_number ||= gateway_options[:order_id].split('-').last
      end

      def order
        @order ||= Spree::Order.find_by!(number: order_number)
      end
    end
  end
end
