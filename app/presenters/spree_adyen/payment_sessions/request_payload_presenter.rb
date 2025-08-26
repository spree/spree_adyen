module SpreeAdyen
  module PaymentSessions
    class RequestPayloadPresenter
      DEFAULT_PARAMS = {
        recurringProcessingModel: 'UnscheduledCardOnFile',
        shopperInteraction: 'Ecommerce',
        storePaymentMethodMode: 'enabled'
      }.freeze

      def initialize(order:, amount:, user:, merchant_account:, payment_method:, channel:, return_url:)
        @order = order
        @amount = amount
        @user = user
        @merchant_account = merchant_account
        @payment_method = payment_method
        @channel = channel
        @return_url = return_url
      end

      def to_h
        {
          metadata: { # unfortunately metadata is not always available in webhooks, even for AUTHORISATION events
            spree_payment_method_id: payment_method.id,
            spree_order_id: order_number
          },
          amount: {
            value: Spree::Money.new(amount, currency: currency).cents,
            currency: currency
          },
          returnUrl: return_url,
          reference: reference,
          countryCode: address.country_iso,
          lineItems: line_items,
          merchantAccount: merchant_account,
          merchantOrderReference: order_number,
          expiresAt: expires_at
        }.merge!(shopper_details, DEFAULT_PARAMS, channel_params, SpreeAdyen::ApplicationInfoPresenter.new.to_h)
      end

      private

      attr_reader :order, :amount, :user, :merchant_account, :payment_method, :channel, :return_url

      delegate :number, to: :order, prefix: true
      delegate :currency, to: :order

      # since we cannot count on metadata reference is the simplest way to store data for webhooks
      # so let's keep its format as ORDERNUMBER_PAYMENTMETHODID_UNIQGUARANTER
      def reference
        [
          order.number,
          payment_method.id,
          order.adyen_payment_sessions.with_deleted.count + 1
        ].join('_')
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
            firstName: address.firstname,
            lastName: address.lastname
          },
          shopperEmail: order.email,
          shopperReference: shopper_reference
        }
      end

      # we need to send reference even for guest users, otherwise we can't tokenize the card
      def shopper_reference
        if user.present?
          "customer_#{user.id}"
        else
          "guest_#{order.number}"
        end
      end

      def address
        @address ||= order.bill_address || order.ship_address
      end

      def line_items
        order.line_items.map do |line_item|
          {
            amountExcludingTax: Spree::Money.new(line_item.price - line_item.included_tax_total, currency: currency).cents,
            amountIncludingTax: Spree::Money.new(line_item.price + line_item.additional_tax_total, currency: currency).cents,
            description: line_item.name,
            id: line_item.id,
            sku: line_item.sku,
            quantity: line_item.quantity
          }
        end
      end

      def expires_at
        SpreeAdyen::Config.payment_session_expiration_in_minutes.minutes.from_now.iso8601
      end
    end
  end
end
