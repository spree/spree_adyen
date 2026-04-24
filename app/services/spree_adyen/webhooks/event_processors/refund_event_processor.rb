module SpreeAdyen
  class RefundError < StandardError; end

  module Webhooks
    module EventProcessors
      class RefundEventProcessor
        class Error < StandardError; end

        def initialize(event)
          @event = event
        end

        def call
          Rails.logger.info("[SpreeAdyen][#{event_id}]: Started processing refund event")
          order = Spree::Order.find_by!(number: event.order_number)

          order.with_lock do
            payment_method = SpreeAdyen::Gateway.find(event.payment_method_id)
            payment = order.payments.find_by!(response_code: event.fetch('originalReference'), payment_method: payment_method)
            refund = payment.refunds.find_by!(transaction_id: event.psp_reference)

            if event.success? && event.code != 'REFUND_FAILED'
              refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_SUBMITTED)
              refund.get_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY)&.destroy
            else
              refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_REJECTED)
              refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY, event.fetch('reason'))

              Rails.error.report(
                SpreeAdyen::RefundError.new(event.fetch('reason')),
                context: { order_id: order.id, refund_id: refund.id, event: event.payload },
                source: 'spree_adyen'
              )
            end
          end

          Rails.logger.info("[SpreeAdyen][#{event_id}]: Finished processing refund event")
        end

        private

        attr_reader :event

        delegate :id, to: :event, prefix: true
      end
    end
  end
end
