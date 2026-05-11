module Spree
  class PaymentSetupSessions::Adyen < PaymentSetupSession
    delegate :preferred_client_key, to: :payment_method

    def adyen_id
      external_id
    end

    def session_data
      external_data&.dig('session_data')
    end

    def client_key
      preferred_client_key
    end

    def channel
      external_data&.dig('channel') || Spree::PaymentSessions::Adyen::AVAILABLE_CHANNELS[:web]
    end

    def return_url
      external_data&.dig('return_url')
    end

    def successful?
      status == 'completed'
    end
  end
end
