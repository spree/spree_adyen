module SpreeAdyen
  module PaymentSessions
    class ProcessWithResult
      def initialize(payment_session:, session_result:)
        @payment_session = payment_session
        @session_result = session_result
      end

      def call
        response = payment_session.payment_method.payment_session_result(payment_session.adyen_id, session_result)
        status = response.params.fetch('status')

        order.with_lock do
          payment = order.payments.where(
            payment_method: payment_session.payment_method,
            response_code: payment_session.adyen_id
          ).first_or_initialize

          payment.update!(amount: payment_session.amount, skip_source_requirement: true)
          payment.started_processing! if payment.checkout? # it can be already changed by webhook

          case status
          when 'completed'
            payment_session.complete! if payment_session.can_complete?
            payment.confirm!
            Spree::Dependencies.checkout_complete_service.constantize.call(order: order) unless order.completed?
          when 'canceled'
            payment.void! if payment.can_void?
            payment_session.cancel! unless payment_session.canceled?
          when 'refused', 'expired'
            payment.failure! unless payment.failed?
            payment_session.refuse! unless payment_session.refused?
          when 'paymentPending'
            payment_session.pending! if payment_session.can_pending? # this can have other status after
          else
            Rails.error.unexpected('Unexpected payment status', context: { order_id: order.id, status: status },
                                                                source: 'spree_adyen')
          end
        end
      end

      private

      attr_reader :payment_session, :session_result

      delegate :order, to: :payment_session
    end
  end
end
