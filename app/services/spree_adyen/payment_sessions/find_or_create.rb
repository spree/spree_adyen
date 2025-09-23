module SpreeAdyen
  module PaymentSessions
    class FindOrCreate
      REQUIRED_ORDER_STATE = 'payment'.freeze

      def initialize(order:, user:, amount:, payment_method:)
        @order = order
        @amount = amount
        @user = user
        @payment_method = payment_method
      end

      def call
        return unless order.can_create_adyen_payment_session?
        return payment_session if payment_session.present?

        SpreeAdyen::PaymentSession.create!(
          order: order,
          amount: amount,
          currency: order.currency,
          user: user,
          payment_method: payment_method,
          channel: SpreeAdyen::PaymentSession::AVAILABLE_CHANNELS[:web]
        )
      end

      private

      attr_reader :order, :payment_method, :amount, :user

      def payment_session
        @payment_session ||= PaymentSession.with_status(:initial).not_expired.find_by(
          payment_method: payment_method,
          order: order,
          currency: order.currency,
          user: user,
          amount: amount,
          channel: SpreeAdyen::PaymentSession::AVAILABLE_CHANNELS[:web]
        )
      end
    end
  end
end
