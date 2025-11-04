module SpreeAdyen
  module PaymentSessions
    class FindOrCreate
      prepend ::Spree::ServiceModule::Base

      def initialize(order:, user:, amount:, payment_method:, channel: nil, return_url: nil)
        @order = order
        @amount = amount
        @user = user
        @payment_method = payment_method
        @channel = channel || SpreeAdyen::PaymentSession::AVAILABLE_CHANNELS[:web]
        @return_url = return_url
      end

      def call
        return failure(nil, "Cannot create Adyen payment session for the order in the #{order.state} state") unless order.can_create_adyen_payment_session?
        return success(payment_session) if payment_session.present?

        create_attributes = {
          order: order,
          amount: amount,
          currency: order.currency,
          user: user,
          payment_method: payment_method,
          channel: channel
        }
        create_attributes[:return_url] = return_url if return_url.present?

        payment_session = SpreeAdyen::PaymentSession.create(create_attributes)
        payment_session.persisted? ? success(payment_session) : failure(payment_session)
      end

      private

      attr_reader :order, :payment_method, :amount, :user, :channel, :return_url

      def payment_session
        find_attributes = {
          payment_method: payment_method,
          order: order,
          currency: order.currency,
          user: user,
          amount: amount,
          channel: channel
        }

        @payment_session ||= PaymentSession.with_status(:initial).not_expired.find_by(find_attributes)
      end
    end
  end
end
