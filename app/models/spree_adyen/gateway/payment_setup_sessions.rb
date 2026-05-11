module SpreeAdyen
  class Gateway < ::Spree::Gateway
    module PaymentSetupSessions
      extend ActiveSupport::Concern

      def setup_session_supported?
        true
      end

      def payment_setup_session_class
        Spree::PaymentSetupSessions::Adyen
      end

      # Creates an Adyen zero-auth tokenization session via the Sessions API
      # and persists a Spree::PaymentSetupSessions::Adyen record.
      #
      # @param customer [Spree::User] the customer to vault the payment method for
      # @param external_data [Hash] additional data (e.g., channel, return_url, currency)
      # @return [Spree::PaymentSetupSessions::Adyen] the created setup session
      def create_payment_setup_session(customer:, external_data: {})
        channel = external_data[:channel] || external_data['channel'] || Spree::PaymentSessions::Adyen::AVAILABLE_CHANNELS[:web]
        return_url = external_data[:return_url] || external_data['return_url'] || default_setup_return_url
        currency = external_data[:currency] || external_data['currency']

        response = create_adyen_setup_session(customer, channel, return_url, currency)

        payment_setup_session_class.create!(
          customer: customer,
          payment_method: self,
          status: 'pending',
          external_id: response.params['id'],
          external_data: external_data.to_h.stringify_keys.merge(
            'session_data' => response.params['sessionData'],
            'channel' => channel,
            'return_url' => return_url,
            'shopper_reference' => "customer_#{customer.id}"
          )
        )
      end

      # Completes a setup session by checking with Adyen and creating a payment source
      # from the stored payment method. Idempotent — if the source was already created
      # by the AUTHORISATION webhook, returns the session unchanged.
      #
      # @param setup_session [Spree::PaymentSetupSessions::Adyen]
      # @param params [Hash] must include :session_result (or :external_data with :redirect_result)
      def complete_payment_setup_session(setup_session:, params: {})
        session_result = params[:session_result] || params['session_result']

        if session_result.blank?
          external_data = params[:external_data] || params['external_data'] || {}
          redirect_result = external_data[:redirect_result] || external_data['redirect_result']

          raise Spree::Core::GatewayError, 'session_result or redirect_result is required' if redirect_result.blank?

          return complete_setup_session_from_redirect(setup_session, redirect_result)
        end

        complete_setup_session_from_result(setup_session, session_result)
      end

      # Creates a zero-auth tokenization session via Adyen's Sessions API.
      #
      # @param customer [Spree::User]
      # @param channel [String] Web, iOS, Android
      # @param return_url [String]
      # @param currency [String, nil] defaults to USD
      # @return [Spree::PaymentResponse]
      def create_adyen_setup_session(customer, channel, return_url, currency = nil)
        payload = SpreeAdyen::PaymentSetupSessions::RequestPayloadPresenter.new(
          customer: customer,
          merchant_account: preferred_merchant_account,
          payment_method: self,
          channel: channel,
          return_url: return_url,
          currency: currency
        ).to_h

        response = send_request do
          client.checkout.payments_api.sessions(payload, headers: { 'Idempotency-Key' => SecureRandom.uuid })
        end
        response_body = response.response

        if response.status.to_i == 201
          success(response_body.id, response_body)
        else
          failure(response_body.slice('pspReference', 'message').values.join(' - '))
        end
      end

      private

      def complete_setup_session_from_result(setup_session, session_result)
        response = payment_session_result(setup_session.external_id, session_result)
        status = response.params.fetch('status')
        process_setup_session_status(setup_session, status, response.params)
      end

      def complete_setup_session_from_redirect(setup_session, redirect_result)
        response = send_request do
          client.checkout.payments_api.payments_details({ details: { redirectResult: redirect_result } })
        end
        result_code = response.response&.dig('resultCode')
        status = case result_code
                 when 'Authorised' then 'completed'
                 when 'Pending', 'Received' then 'paymentPending'
                 when 'Cancelled' then 'canceled'
                 when 'Refused', 'Error' then 'refused'
                 else result_code
                 end
        process_setup_session_status(setup_session, status, response.response || {})
      end

      def process_setup_session_status(setup_session, status, response_params)
        case status
        when 'completed'
          create_source_from_session_result(setup_session, response_params)
          setup_session.complete if setup_session.can_complete?
        when 'canceled'
          setup_session.cancel if setup_session.can_cancel?
        when 'refused', 'expired'
          setup_session.fail if setup_session.can_fail?
        when 'paymentPending'
          setup_session.process if setup_session.can_process?
        else
          Rails.error.unexpected(
            'Unexpected Adyen setup session status',
            context: { setup_session_id: setup_session.id, status: status },
            source: 'spree_adyen'
          )
        end

        setup_session
      end

      # Creates a payment source from the Adyen Sessions result payload.
      # Card details (last4/expiry) may be missing — they are backfilled by the
      # AUTHORISATION webhook via SpreeAdyen::PaymentSetupSessions::HandleAuthorisation.
      # Idempotent: if the webhook already created the source, this is a no-op.
      def create_source_from_session_result(setup_session, response_params)
        return if setup_session.payment_source.present?

        source = SpreeAdyen::PaymentSetupSessions::CreateSourceFromResult.new(
          setup_session: setup_session,
          response_params: response_params
        ).call

        setup_session.update!(payment_source: source) if source.present?
      end

      def default_setup_return_url
        store = stores.first
        return nil unless store

        "#{store.storefront_url}/adyen/payment_setup_sessions/redirect"
      end
    end
  end
end
