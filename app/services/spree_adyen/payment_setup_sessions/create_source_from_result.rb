module SpreeAdyen
  module PaymentSetupSessions
    # Creates a payment source from an Adyen Sessions result payload (the synchronous
    # complete-session response, not a webhook). Cards may be missing last4/expiry —
    # those are backfilled by the AUTHORISATION webhook handler.
    class CreateSourceFromResult
      def initialize(setup_session:, response_params:)
        @setup_session = setup_session
        @response_params = response_params.to_h.with_indifferent_access
      end

      def call
        return nil if stored_payment_method_id.blank?

        if credit_card_brand?
          find_or_create_credit_card
        else
          find_or_create_alternative_source
        end
      end

      private

      attr_reader :setup_session, :response_params

      delegate :payment_method, :customer, to: :setup_session

      def additional_data
        @additional_data ||= response_params.fetch('additionalData', {})
      end

      def stored_payment_method_id
        additional_data['tokenization.storedPaymentMethodId'] ||
          additional_data['recurring.recurringDetailReference']
      end

      def payment_method_reference
        @payment_method_reference ||= additional_data['paymentMethod']&.to_sym
      end

      def credit_card_brand?
        payment_method_reference.present? &&
          payment_method_reference.in?(SpreeAdyen::Config.credit_card_sources)
      end

      def find_or_create_credit_card
        payment_method.credit_cards.capturable.find_or_create_by(
          gateway_payment_profile_id: stored_payment_method_id
        ) do |cc|
          cc.user = customer
          cc.payment_method = payment_method
          cc.cc_type = SpreeAdyen::Webhooks::CreditCardPresenter::CREDIT_CARD_BRANDS.fetch(
            payment_method_reference.to_s, payment_method_reference.to_s
          )
        end
      end

      def find_or_create_alternative_source
        source_klass = SpreeAdyen::Webhooks::Actions::CreateSource::SOURCE_KLASS_MAP[payment_method_reference] ||
                       SpreeAdyen::PaymentSources::Unknown

        source_klass.find_or_create_by(
          gateway_payment_profile_id: stored_payment_method_id,
          payment_method: payment_method
        ) do |source|
          source.user = customer
        end
      end
    end
  end
end
