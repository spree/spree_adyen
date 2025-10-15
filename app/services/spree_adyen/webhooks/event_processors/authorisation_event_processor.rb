module SpreeAdyen
  module Webhooks
    module EventProcessors
      class AuthorisationEventProcessor
        def initialize(event)
          @event = event
        end

        def call
          Rails.logger.info("[SpreeAdyen][#{event_id}]: Started processing")
          order = Spree::Order.find_by!(number: event.order_number)

          order.with_lock do
            payment_method = SpreeAdyen::Gateway.find(event.payment_method_id)
            # session_id is available only for session based payments so payment_session can be nil
            payment_session = order.adyen_payment_sessions.find_by(adyen_id: event.session_id)
            source = SpreeAdyen::Webhooks::Actions::CreateSource.new(event: event, payment_method: payment_method, user: order.user).call
            # create or find payment
            # atm payment should be already created for web channel (but there is no payment for mobile channels)
            # for web channel payment response code is updated from session_id to psp_reference
            # psp_reference is required for refund flow but is not available before this event
            payment_session&.lock!
            payment = Spree::Payment.find_or_initialize_by(
              response_code: event.session_id || event.psp_reference,
              payment_method: payment_method
            ).tap do |payment|
              payment.assign_attributes(
                skip_source_requirement: true,
                response_code: event.psp_reference,
                amount: event.amount.to_d,
                order: order,
                source: source,
                state: 'processing'
              )
              payment.save!
            end

            if event.success?
              payment.complete! if payment.processing?
              payment_session&.complete
              Spree::Dependencies.checkout_complete_service.constantize.call(order: order) unless order.completed?
            else
              payment.failure!
              payment_session&.refuse
              if order.completed?
                Rails.error.unexpected('Payment failed for previously completed order', context: { order_id: order.id, event: event.payload },
                                                                                        source: 'spree_adyen')
              end
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
