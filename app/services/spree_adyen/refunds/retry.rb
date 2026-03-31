module SpreeAdyen
  module Refunds
    class Retry
      prepend Spree::ServiceModule::Base

      def call(refund:)
        refund.with_lock do
          return failure('Refund is not rejected') unless refund.adyen_refund_status == SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_REJECTED

          payment = refund.payment
          credit_cents = Spree::Money.new(refund.amount.to_f, currency: refund.currency).amount_in_cents

          response = payment.payment_method.credit(credit_cents, payment.source, payment.transaction_id, originator: refund)

          if response.success?
            refund.update_columns(transaction_id: response.authorization)
            refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_PENDING)
            refund.get_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY)&.destroy

            success(refund)
          else
            failure(response.params['message'] || response.message)
          end
        end
      rescue Spree::Core::GatewayError => e
        failure(e.message)
      end
    end
  end
end
