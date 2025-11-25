module SpreeAdyen
  class CancellationError < StandardError; end

  module Webhooks
    module EventProcessors
      class CancellationEventProcessor
        class Error < StandardError; end

        def initialize(event)
          @event = event
        end

        def call
          Rails.logger.info("[SpreeAdyen][#{event_id}]: Started processing")
          order = Spree::Order.find_by!(number: event.order_number)

          order.with_lock do
            payment_method = SpreeAdyen::Gateway.find(event.payment_method_id)
            payment = Spree::Payment.find_by!(response_code: event.fetch('originalReference'), payment_method: payment_method)

            if event.success?
              payment.set_metafield(SpreeAdyen::Gateway::CANCELLATION_PSP_REFERENCE_METAFIELD_KEY, event.psp_reference)
              payment.started_processing!
              payment.void!
            else
              payment.add_gateway_processing_error("Cancellation failed: #{event.fetch('reason')}")
              payment.started_processing! if payment.can_started_processing?
              payment.pend! if payment.can_pend?

              Rails.error.report(
                SpreeAdyen::CancellationError.new(event.fetch('reason')),
                context: { order_id: order.id, event: event.payload },
                source: 'spree_adyen'
              )
            end
          end

          Rails.logger.info("[SpreeAdyen][#{event_id}]: Finished processing")
        end

        private

        attr_reader :event

        delegate :id, to: :event, prefix: true
      end
    end
  end
end
