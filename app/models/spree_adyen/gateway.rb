module SpreeAdyen
  class Gateway < ::Spree::Gateway
    include PaymentSessions

    CAPTURE_PSP_REFERENCE_METAFIELD_KEY = 'adyen.capture_psp_reference'.freeze
    CANCELLATION_PSP_REFERENCE_METAFIELD_KEY = 'adyen.cancellation_psp_reference'.freeze

    #
    # Attributes
    #
    attribute :skip_auto_configuration, :boolean, default: false
    attribute :skip_api_key_validation, :boolean, default: false

    preference :api_key, :password
    preference :merchant_account, :string
    preference :client_key, :password
    preference :hmac_key, :password
    preference :test_mode, :boolean, default: true
    preference :webhook_id, :string
    preference :live_url_prefix, :string

    has_one_attached :apple_developer_merchantid_domain_association, service: Spree.private_storage_service_name

    store_accessor :private_metadata, :previous_hmac_key
    #
    # Validations
    #
    validates :preferred_api_key, presence: true
    validates :preferred_live_url_prefix, presence: true, unless: :preferred_test_mode
    validate :validate_api_key, if: -> { preferred_api_key_changed? }, unless: :skip_api_key_validation

    #
    # Callbacks
    #
    after_commit :configure, if: :preferred_api_key_previously_changed?, unless: :skip_auto_configuration

    #
    # Associations
    #
    has_many :payment_sessions, class_name: 'SpreeAdyen::PaymentSession',
                                foreign_key: 'payment_method_id',
                                dependent: :delete_all,
                                inverse_of: :payment_method

    # @param amount_in_cents [Integer] the amount in cents to capture
    # @param payment_source [Spree::CreditCard | Spree::PaymentSource]
    # @param gateway_options [Hash] this is an instance of Spree::Payment::GatewayOptions.to_hash
    def purchase(amount_in_cents, payment_source, gateway_options = {})
      handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options)
    end

    # @param amount_in_cents [Integer] the amount in cents to capture
    # @param payment_source [Spree::CreditCard | Spree::PaymentSource]
    # @param gateway_options [Hash] this is an instance of Spree::Payment::GatewayOptions.to_hash
    def authorize(amount_in_cents, payment_source, gateway_options = {})
      handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options)
    end

    def handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options = {})
      payload = SpreeAdyen::Payments::RequestPayloadPresenter.new(
        source: payment_source,
        amount_in_cents: amount_in_cents,
        manual_capture: !auto_capture?,
        gateway_options: gateway_options
      ).to_h

      response = send_request do
        client.checkout.payments_api.payments(payload, headers: { 'Idempotency-Key' => SecureRandom.uuid })
      end
      response_body = response.response

      if response.status.to_i == 200
        success(response_body.pspReference, response_body)
      else
        failure(response_body.slice('pspReference', 'message').values.join(' - '))
      end
    end

    def cancel(id, payment)
      transaction_id = id
      payment ||= Spree::Payment.find_by(response_code: id)
      if payment.completed?
        amount = payment.credit_allowed
        return success(transaction_id, {}) if amount.zero?
        # Don't create a refund if the payment is for a shipment, we will create a refund for the whole shipping cost instead
        return success(transaction_id, {}) if payment.respond_to?(:for_shipment?) && payment.for_shipment?

        refund = payment.refunds.create!(
          amount: amount,
          reason: Spree::RefundReason.order_canceled_reason,
          refunder_id: payment.order.canceler_id
        )

        # Spree::Refund#response has the response from the `credit` action
        # For the authorization ID we need to use the payment.response_code
        # Otherwise we'll overwrite the payment authorization with the refund ID
        success(transaction_id, refund.response.params)
      else
        payment.void!
        success(transaction_id, {})
      end
    end

    def credit(amount_in_cents, _source, payment_id, gateway_options = {})
      refund = gateway_options[:originator]
      payment = refund.present? ? refund.payment : Spree::Payment.find_by(response_code: payment_id)

      return failure("#{payment_id} - Payment not found") unless payment

      payload = SpreeAdyen::RefundPayloadPresenter.new(
        payment: payment,
        amount_in_cents: amount_in_cents,
        payment_method: self,
        currency: payment.currency,
        refund: refund
      ).to_h

      response = send_request do
        client.checkout.modifications_api.refund_captured_payment(payload, payment.transaction_id, headers: { 'Idempotency-Key' => SecureRandom.uuid })
      end

      if response.status.to_i == 201
        success(response.response['pspReference'], response)
      else
        failure(response.response.slice('pspReference', 'message').values.join(' - '))
      end
    end

    def request_capture(amount_in_cents, response_code, _gateway_options = {})
      payment = Spree::Payment.find_by(response_code: response_code)

      return failure("#{response_code} - Payment not found") if payment.blank?
      return failure("#{response_code} - Payment is already captured") if payment.completed?

      payload = SpreeAdyen::CapturePayloadPresenter.new(
        amount_in_cents: amount_in_cents,
        payment: payment,
        payment_method: self
      ).to_h

      response = send_request do
        client.checkout.modifications_api.capture_authorised_payment(
          payload,
          payment.response_code,
          headers: { 'Idempotency-Key' => SecureRandom.uuid }
        )
      end

      if response.status.to_i == 201
        success(response.response['paymentPspReference'], response)
      else
        failure(response.response.slice('paymentPspReference', 'message').values.join(' - '))
      end
    end

    # This only checks if the capture was successful by checking the presence of the capture PSP reference
    # The actual capture is requested in #request_capture and handled in the SpreeAdyen::Webhooks::EventProcessors::CaptureEventProcessor
    def capture(amount_in_cents, response_code, _gateway_options = {})
      payment = Spree::Payment.find_by(response_code: response_code)

      return failure("#{response_code} - Payment not found") if payment.blank?
      return failure("#{response_code} - Payment is already captured") if payment.completed?
      return failure("#{response_code} - Capture PSP reference not found") unless payment.has_metafield?(CAPTURE_PSP_REFERENCE_METAFIELD_KEY)

      success(payment.response_code, {})
    end

    def request_void(response_code, _source, _gateway_options)
      payment = Spree::Payment.find_by(response_code: response_code)

      return failure("#{response_code} - Payment not found") if payment.blank?
      return failure("#{response_code} - Payment is already void") if payment.void?

      payload = SpreeAdyen::CancelPayloadPresenter.new(
        payment: payment,
        payment_method: self
      ).to_h

      response = send_request do
        client.checkout.modifications_api.cancel_authorised_payment_by_psp_reference(
          payload,
          payment.response_code,
          headers: { 'Idempotency-Key' => SecureRandom.uuid }
        )
      end

      if response.status.to_i == 201
        success(response.response['paymentPspReference'], response)
      else
        failure(response.response.slice('paymentPspReference', 'message').values.join(' - '))
      end
    end

    # This only checks if the void was successful by checking the presence of the cancellation PSP reference
    # The actual void is requested in #request_void and handled in the SpreeAdyen::Webhooks::EventProcessors::CancellationEventProcessor
    def void(response_code, _source, _gateway_options)
      payment = Spree::Payment.find_by(response_code: response_code)

      return failure("#{response_code} - Payment not found") if payment.blank?
      return failure("#{response_code} - Payment is already void") if payment.void?
      return failure("#{response_code} - Cancellation PSP reference not found") unless payment.has_metafield?(CANCELLATION_PSP_REFERENCE_METAFIELD_KEY)

      success(payment.response_code, {})
    end

    def provider_class
      self.class
    end

    def environment
      if preferred_test_mode
        :test
      else
        :live
      end
    end

    def create_profile(payment); end

    def payment_session_result(payment_session_id, session_result)
      response = send_request do
        client.checkout.payments_api.get_result_of_payment_session(payment_session_id, query_params: { sessionResult: session_result })
      end
      response_body = response.response

      if response.status.to_i == 200
        success(response_body.id, response_body)
      else
        failure(response_body.slice('pspReference', 'message').values.join(' - '))
      end
    end

    # Creates an Adyen session via the Adyen Sessions API.
    # Used internally by the v3 PaymentSessions module and by the legacy SpreeAdyen::PaymentSession model.
    #
    # @param amount [BigDecimal] the amount
    # @param order [Spree::Order] the order to create a session for
    # @param channel [String] the channel (Web, iOS, Android)
    # @param return_url [String] the return URL after redirect flow
    # @return [Spree::PaymentResponse] the response from the session creation
    def create_adyen_session(amount, order, channel, return_url)
      payload = SpreeAdyen::PaymentSessions::RequestPayloadPresenter.new(
        order: order,
        amount: amount,
        user: order.user,
        merchant_account: preferred_merchant_account,
        payment_method: self,
        channel: channel,
        return_url: return_url
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

    # @return [Boolean] whether payment profiles are supported
    # this is used by spree to determine whenever payment source must be passed to gateway methods
    def payment_profiles_supported?
      true
    end

    def default_name
      'Adyen'
    end

    def method_type
      'spree_adyen'
    end

    def payment_icon_name
      'adyen'
    end

    def description_partial_name
      'spree_adyen'
    end

    def configuration_guide_partial_name
      'spree_adyen'
    end

    def custom_form_fields_partial_name
      'spree_adyen'
    end

    def gateway_dashboard_payment_url(payment)
      return if payment.transaction_id.blank?

      "https://ca-#{environment}.adyen.com/ca/ca/accounts/showTx.shtml?pspReference=#{payment.transaction_id}&txType=Payment"
    end

    def reusable_sources(order)
      if order.completed?
        sources_by_order order
      elsif order.user.present?
        credit_cards.where(user_id: order.user_id)
      else
        []
      end
    end

    def get_api_credential_details
      response = client.management.my_api_credential_api.get_api_credential_details

      if response.status.to_i == 200
        success(response.response.id, response.response)
      else
        failure(response.response.message)
      end
    rescue Adyen::AuthenticationError, Adyen::PermissionError
      raise
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e)['message'])
    end

    def add_allowed_origin(domain)
      response = client.management.my_api_credential_api.add_allowed_origin({ domain: domain })

      if response.status.to_i == 200
        success(response.response.id, response.response)
      else
        failure(response.response)
      end
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e))
    end

    def set_up_webhook(url)
      payload = SpreeAdyen::WebhookPayloadPresenter.new(url).to_h
      response = client.management.webhooks_merchant_level_api.set_up_webhook(payload, preferred_merchant_account)

      if response.status.to_i == 200
        success(response.response.id, response.response)
      else
        failure(response.response)
      end
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e)['message'])
    end

    def test_webhook
      response = client.management.webhooks_merchant_level_api.test_webhook({ types: ['AUTHORISATION'] }, preferred_merchant_account,
                                                                            preferred_webhook_id)

      if response.status.to_i == 200 && response.response.dig('data', 0, 'status') == 'success'
        success(nil, response.response)
      else
        failure(response.response)
      end
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e)['message'])
    end

    def generate_hmac_key
      response = client.management.webhooks_merchant_level_api.generate_hmac_key(preferred_merchant_account, preferred_webhook_id)

      if response.status.to_i == 200
        success(response.response.hmacKey, response.response)
      else
        failure(response.response)
      end
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e)['message'])
    end

    def generate_client_key
      response = client.management.my_api_credential_api.generate_client_key

      if response.status.to_i == 200
        success(response.response.clientKey, response.response)
      else
        failure(response.response.message)
      end
    rescue Adyen::AdyenError => e
      failure(parse_adyen_error_response(e)['message'])
    end

    def apple_domain_association_file_content
      @apple_domain_association_file_content ||= apple_developer_merchantid_domain_association&.download
    end

    private

    def validate_api_key
      return if preferred_api_key.blank?

      get_api_credential_details
    rescue Adyen::AuthenticationError => e
      errors.add(:preferred_api_key, "is invalid. Response: #{e.msg}")
    rescue Adyen::PermissionError => e
      errors.add(:preferred_api_key, "has insufficient permissions. Add missing roles to API credential. Response: #{e.msg}")
    rescue Adyen::AdyenError => e
      errors.add(:preferred_api_key, "An error occurred. Response: #{e.msg}")
    end

    def configure
      return if preferred_api_key.blank?

      SpreeAdyen::Gateways::Configure.new(self).call
    end

    def client
      @client ||= Adyen::Client.new.tap do |client|
        client.api_key = preferred_api_key
        client.env = environment
        client.live_url_prefix = preferred_live_url_prefix if environment == :live
      end
    end

    def send_request
      yield
    rescue Adyen::AdyenError => e
      raise Spree::Core::GatewayError, e.msg
    end

    def parse_adyen_error_response(error)
      JSON.parse(error.response)
    rescue JSON::ParserError, TypeError
      { 'message' => error.msg }
    end

    def success(authorization, full_response)
      Spree::PaymentResponse.new(true, nil, full_response.as_json, authorization: authorization)
    end

    def failure(error = nil)
      Spree::PaymentResponse.new(false, error)
    end
  end
end
