module SpreeAdyen
  module Webhooks
    class CreditCardPresenter
      CREDIT_CARD_BRANDS = {
        'mc' => 'master'
      }.freeze

      def initialize(event)
        @event = event
      end

      def to_h
        {
          name: event.card_details['type'],
          month: event.card_details['expiryDate']&.split('/')&.first,
          year: event.card_details['expiryDate']&.split('/')&.last,
          cc_type: CREDIT_CARD_BRANDS.fetch(payment_method_reference, payment_method_reference),
          last_digits: event.card_details['cardSummary'],
          gateway_customer_profile_id: nil,
          gateway_payment_profile_id: event.stored_payment_method_id
        }
      end

      private

      attr_reader :event, :payment_session

      def payment_method_reference
        @payment_method_reference ||= event.payment_method_reference.to_s.downcase
      end
    end
  end
end
