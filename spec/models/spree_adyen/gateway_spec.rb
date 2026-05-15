require 'spec_helper'

RSpec.describe SpreeAdyen::Gateway do
  subject(:gateway) do
    create(:adyen_gateway,
      stores: [store],
      preferred_api_key: ENV.fetch('ADYEN_TEST_API_KEY', 'secret'),
      preferred_merchant_account: ENV.fetch('ADYEN_TEST_MERCHANT_ACCOUNT', 'SpreeCommerceECOM'),
      preferred_test_mode: test_mode,
      preferred_webhook_id: webhook_id,
      preferred_hmac_key: hmac_key,
      preferred_live_url_prefix: live_url_prefix
    )
  end
  let(:store) { Spree::Store.default }
  let(:amount) { 100 }
  let(:test_mode) { true }
  let(:webhook_id) { '1234567890' }
  let(:hmac_key) { '1234567890' }
  let(:live_url_prefix) { '1797a841fbb37ca7-TestCompany' }

  describe 'validations' do
    describe 'live URL prefix validation' do
      context 'when test_mode is true' do
        let(:test_mode) { true }

        it 'does not require live URL prefix' do
          gateway.preferred_live_url_prefix = nil
          expect(gateway).to be_valid
        end
      end

      context 'when in live mode' do
        let(:test_mode) { false }

        context 'when live URL prefix is blank' do
          let(:live_url_prefix) { nil }

          it 'is invalid' do
            expect { gateway }.to raise_error(ActiveRecord::RecordInvalid, "Validation failed: Preferred live url prefix can't be blank")
          end
        end

        context 'when live URL prefix is present' do
          let(:live_url_prefix) { '1797a841fbb37ca7-TestCompany' }

          it 'is valid' do
            expect(gateway).to be_valid
          end
        end
      end
    end

    describe 'api key validation' do
      before do
        gateway.preferred_api_key = 'new_api_key'
      end

      context 'when skip_api_key_validation is false' do
        before do
          gateway.skip_api_key_validation = false
        end

        context 'with valid api key' do
          it 'does not validate the api key' do
            VCR.use_cassette('management_api/get_api_credential_details/success') do
              expect(gateway).to be_valid
            end
          end
        end

        context 'with invalid api key (401)' do
          it 'is invalid' do
            VCR.use_cassette('management_api/get_api_credential_details/failure_401') do
              expect(gateway).to be_invalid
              expect(gateway.errors.full_messages).to include(a_string_matching(/Preferred api key is invalid. Response:.*ErrorCode: 00_401/))
            end
          end
        end

        context 'with production env and test_mode is true' do
          before do
            allow(Rails.env).to receive(:production?).and_return(true)
          end

          it 'sends requests to test environment' do
            VCR.use_cassette('management_api/get_api_credential_details/success') do
              expect(gateway).to be_valid
            end
          end
        end

        context 'with production env and test_mode is false' do
          let(:test_mode) { false }

          before do
            allow(Rails.env).to receive(:production?).and_return(true)
          end

          it 'sends requests to live environment' do
            VCR.use_cassette('management_api/get_api_credential_details/success_production') do
              expect(gateway).to be_valid
            end
          end
        end

        context 'without required permissions (403)' do
          it 'is invalid' do
            VCR.use_cassette('management_api/get_api_credential_details/failure_403') do
              expect(gateway).to be_invalid
              expect(gateway.errors.full_messages).to include(a_string_matching(/Preferred api key has insufficient permissions. Add missing roles to API credential. Response: Not allowed ErrorCode: 00_403/))
            end
          end
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'after_commit' do
      describe 'auto configuration' do
        let(:configure_double) { double(call: true) }

        before do
          allow(SpreeAdyen::Gateways::Configure).to receive(:new).with(gateway).and_return(configure_double)
          gateway.preferred_api_key = 'new_api_key'
        end

        context 'when skip_auto_configuration is true' do
          before do
            gateway.skip_auto_configuration = true
          end

          it 'does not configure the gateway' do
            expect(configure_double).to_not receive(:call)

            gateway.save
          end
        end

        context 'when skip_auto_configuration is false' do
          before do
            gateway.skip_auto_configuration = false
          end

          it 'configures the gateway' do
            expect(configure_double).to receive(:call).once

            gateway.save
          end
        end
      end
    end
  end

  before do
    allow(Spree).to receive(:version).and_return('42.0.0')
  end

  describe '#payment_session_result' do
    subject { gateway.payment_session_result(payment_session_id, session_result) }

    let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }
    let(:session_result) { 'resultData' }

    context 'with valid params' do
      it 'returns proper (successful) Spree::PaymentResponse instance' do
        VCR.use_cassette('payment_session_results/success/completed') do
          expect(subject).to be_a(Spree::PaymentResponse)
          expect(subject.success?).to be_truthy
          expect(subject.authorization).to eq(payment_session_id)
        end
      end
    end

    context 'with invalid params' do
      let(:session_result) { 'invalid' }

      it 'raises Spree::Core::GatewayError' do
        VCR.use_cassette('payment_session_results/failure') do
          expect { subject }.to raise_error(Spree::Core::GatewayError, 'server could not process request ErrorCode: 701')
        end
      end
    end
  end

  describe '#gateway_dashboard_payment_url' do
    subject { gateway.gateway_dashboard_payment_url(payment) }

    let(:payment) { create(:payment, transaction_id: transaction_id) }

    context 'when payment has a transaction_id' do
      let(:transaction_id) { '1234567890' }

      context 'when test_mode is true' do
        let(:test_mode) { true }

        it 'returns the correct URL' do
          expect(subject).to eq('https://ca-test.adyen.com/ca/ca/accounts/showTx.shtml?pspReference=1234567890&txType=Payment')
        end
      end

      context 'when test_mode is false' do
        let(:test_mode) { false }

        it 'returns the correct URL' do
          expect(subject).to eq('https://ca-live.adyen.com/ca/ca/accounts/showTx.shtml?pspReference=1234567890&txType=Payment')
        end
      end
    end

    context 'when payment has no transaction_id' do
      let(:payment) { create(:payment, transaction_id: nil) }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#create_adyen_session' do
    subject { gateway.create_adyen_session(amount, order, channel, return_url) }

    let(:order) { create(:order_with_line_items) }
    let(:bill_address) { order.bill_address }
    let(:amount) { 100 }
    let(:channel) { 'Web' }
    let(:return_url) { 'http://www.example.com/adyen/payment_sessions/redirect' }
    let(:payment_session_id) { 'CS2BD6B9B093D32284D8EB223' }

    context 'with valid params' do
      it 'returns proper (successful) Spree::PaymentResponse instance' do
        VCR.use_cassette('payment_sessions/success') do
          expect(subject).to be_a(Spree::PaymentResponse)
          expect(subject.success?).to be_truthy
          expect(subject.authorization).to eq(payment_session_id)
        end
      end
    end

    context 'with invalid params' do
      before do
        allow(bill_address).to receive(:country_iso).and_return('INVALID')
      end

      it 'raises Spree::Core::GatewayError' do
        VCR.use_cassette('payment_sessions/failure') do
          expect { subject }.to raise_error(Spree::Core::GatewayError, "Field 'countryCode' is not valid. ErrorCode: 200")
        end
      end
    end
  end

  describe '#generate_client_key' do
    subject { gateway.generate_client_key }

    it 'returns proper (successful) Spree::PaymentResponse instance' do
      VCR.use_cassette('management_api/generate_client_key/success') do
        expect(subject).to be_a(Spree::PaymentResponse)
        expect(subject.success?).to be_truthy
      end
    end
  end

  describe '#environment' do
    subject { gateway.environment }

    context 'when test_mode is true' do
      it { is_expected.to eq(:test) }
    end

    context 'when test_mode is false' do
      let(:gateway) { create(:adyen_gateway, preferred_test_mode: false, preferred_live_url_prefix: live_url_prefix) }

      it { is_expected.to eq(:live) }
    end
  end

  describe '#test_webhook' do
    subject { gateway.test_webhook }

    let(:hmac_key) { 'HMAC_KEY' }

    context 'when webhook is valid' do
      let(:webhook_id) { 'WBHK42CLH22322975N3464F9TP0000' }

      it 'returns success' do
        VCR.use_cassette("management_api/test_webhook/success") do
          expect(subject.success?).to be(true)
        end
      end
    end

    context 'when webhook ID is invalid' do
      let(:webhook_id) { '1234567890' }

      it 'returns failure' do
        VCR.use_cassette("management_api/test_webhook/bad_request") do
          expect(subject.success?).to be(false)
        end
      end
    end

    context 'when webhook does not respond with 2xx' do
      let(:webhook_id) { 'WBHK42CLH22322975N3464F9TP0000' }

      it 'returns failure' do
        VCR.use_cassette("management_api/test_webhook/failure") do
          expect(subject.success?).to be(false)
        end
      end
    end
  end

  describe '#purchase' do
    subject { gateway.purchase(amount_in_cents, payment_source, gateway_options) }

    let(:order) { create(:order_with_line_items, total: 100) }
    let(:payment) { create(:payment, state: 'pending', order: order, payment_method: gateway, amount: 100.0, response_code: nil, source: payment_source) }

    let(:payment_source) do
      create(:credit_card,
        gateway_payment_profile_id: 'stored_cc_id',
        payment_method: gateway,
        cc_type: "master",
        last_digits: "1115",
        month: 3,
        year: 2030,
      )
    end

    let(:amount_in_cents) { 100_00 }
    let(:currency) { 'USD' }
    let(:gateway_options) { { order_id: "#{order.number}-#{payment.id}" } }

    it 'returns proper (successful) Spree::PaymentResponse instance' do
      VCR.use_cassette('payment_api/payments/success') do
        expect(subject).to be_a(Spree::PaymentResponse)
        expect(subject.success?).to be_truthy
        expect(subject.authorization).to eq('ADYEN_PSP_REFERENCE')
      end
    end
  end

  describe '#cancel' do
    subject { gateway.cancel(payment.response_code, payment) }

    let!(:refund_reason) { Spree::RefundReason.first || create(:default_refund_reason) }

    context 'when payment is completed' do
      let(:order) { create(:order, total: 10, number: 'R142767632') }
      let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }

      it 'creates a refund with credit_allowed_amount' do
        VCR.use_cassette("payment_api/create_refund/success") do
          expect { subject }.to change(Spree::Refund, :count).by(1)

          expect(payment.refunds.last.amount).to eq(10.0)
          expect(subject.success?).to be(true)
          expect(subject.authorization).to eq(payment.response_code)
        end
      end

      context 'if amount to refund is zero' do
        let!(:refund) { create(:refund, payment: payment, amount: payment.amount) }

        it 'does not create refund' do
          expect { subject }.not_to change(Spree::Refund, :count)

          expect(subject.success?).to be true
        end
      end
    end

    context 'when payment is not completed' do
      let(:payment) { create(:payment, state: 'processing') }

      it 'voids the payment' do
        expect { subject }.not_to change(Spree::Refund, :count)

        expect(payment.reload.state).to eq('void')
        expect(subject.authorization).to eq(payment.response_code)
      end
    end

    context 'when response is not successful' do
      let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'foobar') }
      let(:order) { create(:order, total: 10, number: 'R142767632') }

      it 'should raises Spree::Core::GatewayError with the error message' do
        VCR.use_cassette("payment_api/create_refund/failure/invalid_payment_id") do
          expect { subject }.to raise_error(Spree::Core::GatewayError, 'Original pspReference required for this operation ErrorCode: 167')
        end
      end
    end
  end

  describe '#credit' do
    subject { gateway.credit(amount_in_cents, payment.source, passed_response_code, gateway_options) }

    let(:order) { create(:order, total: 10, number: 'R142767632') }
    let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:amount_in_cents) { 800 }
    let(:passed_response_code) { payment.response_code }
    let(:refund) { create(:refund, payment: payment, amount: payment.amount) }
    let(:gateway_options) { { originator: refund } }

    it 'refunds some of the payment amount' do
      VCR.use_cassette("payment_api/create_refund/success_partial") do
        expect(subject.success?).to be(true)
        expect(subject.params['response']['amount']['value']).to eq(amount_in_cents)
      end
    end

    context 'when response is not successful' do
      let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
      let(:order) { create(:order, total: 10, number: 'R142767632') }
      let(:amount_in_cents) { 0 }

      it 'raises Spree::Core::GatewayError' do
        VCR.use_cassette("payment_api/create_refund/failure/invalid_amount") do
          expect { subject }.to raise_error(Spree::Core::GatewayError, "Field 'amount' is not valid. ErrorCode: 137")
        end
      end
    end

    context 'when originator is not present' do
      let(:gateway_options) { {} }

      it 'finds payment by response code and refunds the payment' do
        VCR.use_cassette("payment_api/create_refund/success_partial") do
          expect(subject.success?).to be(true)
          expect(subject.params['response']['amount']['value']).to eq(amount_in_cents)
        end
      end
    end

    context 'when payment is not found' do
      let(:gateway_options) { {} }
      let(:passed_response_code) { 'foobar' }

      it 'should return failure response' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("foobar - Payment not found")
      end
    end
  end

  describe '#request_capture' do
    subject { gateway.request_capture(amount_in_cents, response_code) }

    let(:amount_in_cents) { 100_00 }
    let(:response_code) { 'ADYEN_PAYMENT_PSP_REFERENCE' }

    let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: gateway, amount: 100.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:payment_state) { 'pending' }
    let(:order) { create(:order, total: 100) }

    it 'captures the payment' do
      VCR.use_cassette("payment_api/captures/success") do
        expect(subject.success?).to eq(true)
        expect(subject.authorization).to eq(response_code)
      end
    end

    context 'when payment is not found' do
      let(:response_code) { 'foobar' }

      it 'fails to capture the payment' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Payment not found")
      end
    end

    context 'when payment is not pending' do
      let(:payment_state) { 'completed' }

      it 'fails to capture the payment' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Payment is already captured")
      end
    end

    context 'when the response is not successful' do
      it 'raises Spree::Core::GatewayError' do
        VCR.use_cassette("payment_api/captures/failure") do
          expect { subject }.to raise_error(Spree::Core::GatewayError, 'Original pspReference required for this operation ErrorCode: 167')
        end
      end
    end
  end

  describe '#capture' do
    subject { gateway.capture(amount_in_cents, response_code) }

    let(:amount_in_cents) { 100_00 }
    let(:response_code) { 'ADYEN_PAYMENT_PSP_REFERENCE' }

    let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: gateway, amount: 100.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:payment_state) { 'pending' }
    let(:order) { create(:order, total: 100) }

    context 'when the capture request was successful' do
      before do
        payment.set_metafield(SpreeAdyen::Gateway::CAPTURE_PSP_REFERENCE_METAFIELD_KEY, 'ADYEN_CAPTURE_PSP_REFERENCE')
      end

      it 'returns success' do
        expect(subject.success?).to eq(true)
        expect(subject.authorization).to eq(response_code)
      end

      context 'when the payment is not found' do
        let(:response_code) { 'foobar' }

        it 'returns failure' do
          expect(subject.success?).to eq(false)
          expect(subject.message).to eq("#{response_code} - Payment not found")
        end
      end

      context 'when the payment is already captured' do
        let(:payment_state) { 'completed' }

        it 'returns failure' do
          expect(subject.success?).to eq(false)
          expect(subject.message).to eq("#{response_code} - Payment is already captured")
        end
      end
    end

    context 'when the capture request was not successful' do
      it 'returns failure' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Capture PSP reference not found")
      end
    end
  end

  describe '#request_void' do
    subject { gateway.request_void(response_code, nil, {}) }

    let(:response_code) { 'ADYEN_PAYMENT_PSP_REFERENCE' }

    let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: gateway, amount: 100.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:payment_state) { 'pending' }
    let(:order) { create(:order, total: 100) }

    it 'voids the payment' do
      VCR.use_cassette("payment_api/voids/success") do
        expect(subject.success?).to eq(true)
        expect(subject.authorization).to eq(response_code)
      end
    end

    context 'when payment is not found' do
      let(:response_code) { 'foobar' }

      it 'fails to void the payment' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Payment not found")
      end
    end

    context 'when payment is already voided' do
      let(:payment_state) { 'void' }

      it 'fails to void the payment' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Payment is already void")
      end
    end

    context 'when the response is not successful' do
      it 'raises Spree::Core::GatewayError' do
        VCR.use_cassette("payment_api/voids/failure") do
          expect { subject }.to raise_error(Spree::Core::GatewayError, 'Original pspReference required for this operation ErrorCode: 167')
        end
      end
    end
  end

  describe '#void' do
    subject { gateway.void(response_code, nil, {}) }

    let(:response_code) { 'ADYEN_PAYMENT_PSP_REFERENCE' }

    let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: gateway, amount: 100.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:payment_state) { 'void_pending' }
    let(:order) { create(:order, total: 100) }

    context 'when the void request was successful' do
      before do
        payment.set_metafield(SpreeAdyen::Gateway::CANCELLATION_PSP_REFERENCE_METAFIELD_KEY, 'ADYEN_CANCELLATION_PSP_REFERENCE')
      end

      it 'returns success' do
        expect(subject.success?).to eq(true)
        expect(subject.authorization).to eq(response_code)
      end

      context 'when the payment is not found' do
        let(:response_code) { 'foobar' }

        it 'returns failure' do
          expect(subject.success?).to eq(false)
          expect(subject.message).to eq("#{response_code} - Payment not found")
        end
      end

      context 'when the payment is already voided' do
        let(:payment_state) { 'void' }

        it 'returns failure' do
          expect(subject.success?).to eq(false)
          expect(subject.message).to eq("#{response_code} - Payment is already void")
        end
      end
    end

    context 'when the void request was not successful' do
      it 'returns failure' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("#{response_code} - Cancellation PSP reference not found")
      end
    end
  end

  describe '#set_up_webhook' do
    subject { gateway.set_up_webhook(url) }
    let(:url) { "https://9866bd85ee50.ngrok-free.app/adyen/webhooks" }

    around do |example|
      Timecop.freeze(Time.zone.local(2025, 1, 1, 13, 12, 0)) { example.run }
    end

    it 'creates a webhook' do
      VCR.use_cassette("management_api/create_webhook/success") do
        expect(subject.success?).to be(true)
      end
    end
  end

  describe '#webhook_url' do
    it 'returns the core webhook url by default' do
      expect(gateway.webhook_url).to eq("#{store.formatted_url}/api/v3/webhooks/payments/#{gateway.prefixed_id}")
    end

    context 'with legacy webhook handlers enabled' do
      before do
        allow(SpreeAdyen::Config).to receive(:[]).and_call_original
        allow(SpreeAdyen::Config).to receive(:[]).with(:use_legacy_webhook_handlers).and_return(true)
      end

      it 'returns the legacy webhook url' do
        expect(gateway.webhook_url).to eq("#{store.formatted_url}/adyen/webhooks")
      end
    end
  end

  describe '#complete_payment_session' do
    let(:order) { create(:order_with_line_items, store: store) }
    let!(:payment_session) do
      Spree::PaymentSessions::Adyen.create!(
        order: order,
        payment_method: gateway,
        amount: order.total,
        currency: order.currency,
        status: 'pending',
        external_id: 'CS4FBB6F827EC53AC7',
        external_data: { 'session_data' => 'test', 'channel' => 'Web' }
      )
    end

    context 'with session_result' do
      it 'completes the payment session and completes the payment (auto_capture)' do
        VCR.use_cassette('payment_session_results/success/completed') do
          gateway.complete_payment_session(payment_session: payment_session, params: { session_result: 'resultData' })

          expect(payment_session.reload.status).to eq('completed')
          payment = payment_session.order.payments.find_by(response_code: payment_session.external_id)
          expect(payment.state).to eq('completed')
        end
      end

      context 'when gateway has auto_capture disabled (manual capture)' do
        before { gateway.update!(auto_capture: false) }

        it 'completes the payment session but leaves the payment in pending' do
          VCR.use_cassette('payment_session_results/success/completed') do
            gateway.complete_payment_session(payment_session: payment_session, params: { session_result: 'resultData' })

            expect(payment_session.reload.status).to eq('completed')
            payment = payment_session.order.payments.find_by(response_code: payment_session.external_id)
            expect(payment.state).to eq('pending')
          end
        end
      end
    end

    context 'with redirect_result in external_data' do
      let(:payments_details_response) do
        double(response: { 'resultCode' => 'Authorised', 'pspReference' => 'psp_123' })
      end

      before do
        allow(gateway).to receive(:send_request).and_yield.and_return(payments_details_response)
        allow(gateway.send(:client).checkout.payments_api).to receive(:payments_details).and_return(double(status: 200, response: payments_details_response.response))
      end

      it 'calls /payments/details and completes the payment session' do
        gateway.complete_payment_session(
          payment_session: payment_session,
          params: { external_data: { redirect_result: 'redirectResultToken' } }
        )
        expect(payment_session.reload.status).to eq('completed')
      end
    end

    context 'with neither session_result nor redirect_result' do
      it 'raises a gateway error' do
        expect {
          gateway.complete_payment_session(payment_session: payment_session, params: {})
        }.to raise_error(Spree::Core::GatewayError, 'session_result or redirect_result is required')
      end
    end
  end

  describe '#parse_webhook_event' do
    let(:order) { create(:order_with_line_items, store: store) }
    let!(:payment_session) do
      Spree::PaymentSessions::Adyen.create!(
        order: order,
        payment_method: gateway,
        amount: order.total,
        currency: order.currency,
        status: 'pending',
        external_id: 'CS_test_session_123',
        external_data: { 'session_data' => 'test', 'channel' => 'Web' }
      )
    end

    let(:authorisation_payload) do
      {
        'notificationItems' => [{
          'NotificationRequestItem' => {
            'eventCode' => 'AUTHORISATION',
            'success' => 'true',
            'pspReference' => 'psp_test_123',
            'merchantReference' => "#{order.number}_#{gateway.id}",
            'amount' => { 'value' => 1000, 'currency' => 'USD' },
            'paymentMethod' => 'visa',
            'additionalData' => { 'checkoutSessionId' => 'CS_test_session_123' }
          }
        }]
      }
    end

    before do
      allow(gateway).to receive(:valid_hmac?).and_return(true)
    end

    context 'with AUTHORISATION success event' do
      it 'returns authorized action with payment session' do
        result = gateway.parse_webhook_event(authorisation_payload.to_json, {})

        expect(result[:action]).to eq(:authorized)
        expect(result[:payment_session]).to eq(payment_session)
      end
    end

    context 'with AUTHORISATION failure event' do
      before do
        authorisation_payload['notificationItems'][0]['NotificationRequestItem']['success'] = 'false'
      end

      it 'returns failed action' do
        result = gateway.parse_webhook_event(authorisation_payload.to_json, {})

        expect(result[:action]).to eq(:failed)
        expect(result[:payment_session]).to eq(payment_session)
      end
    end

    context 'with CAPTURE event' do
      before do
        authorisation_payload['notificationItems'][0]['NotificationRequestItem']['eventCode'] = 'CAPTURE'
      end

      it 'returns captured action' do
        result = gateway.parse_webhook_event(authorisation_payload.to_json, {})

        expect(result[:action]).to eq(:captured)
      end
    end

    context 'with CANCELLATION event' do
      before do
        authorisation_payload['notificationItems'][0]['NotificationRequestItem']['eventCode'] = 'CANCELLATION'
      end

      it 'returns canceled action' do
        result = gateway.parse_webhook_event(authorisation_payload.to_json, {})

        expect(result[:action]).to eq(:canceled)
      end
    end

    context 'when the session is a PaymentSetupSession (zero-auth tokenization)' do
      let!(:setup_session) do
        Spree::PaymentSetupSessions::Adyen.create!(
          payment_method: gateway,
          customer: create(:user),
          status: 'pending',
          external_id: 'CS_setup_for_webhook'
        )
      end

      let(:setup_payload) do
        {
          'notificationItems' => [{
            'NotificationRequestItem' => {
              'eventCode' => 'AUTHORISATION',
              'success' => 'true',
              'pspReference' => 'psp_setup_111',
              'merchantReference' => "SETUP_#{gateway.id}_abc",
              'amount' => { 'value' => 0, 'currency' => 'USD' },
              'paymentMethod' => 'visa',
              'additionalData' => {
                'checkoutSessionId' => 'CS_setup_for_webhook',
                'tokenization.storedPaymentMethodId' => 'TOKEN_VISA_777',
                'cardSummary' => '1111',
                'expiryDate' => '06/2031'
              }
            }
          }]
        }
      end

      it 'processes the setup session inline and returns nil so core does not dispatch' do
        expect(SpreeAdyen::PaymentSetupSessions::HandleAuthorisation).to receive(:new).and_call_original

        result = gateway.parse_webhook_event(setup_payload.to_json, {})

        expect(result).to be_nil
        expect(setup_session.reload.status).to eq('completed')
        expect(setup_session.payment_source).to be_present
      end
    end

    context 'with unsupported event' do
      before do
        authorisation_payload['notificationItems'][0]['NotificationRequestItem']['eventCode'] = 'REFUND'
      end

      it 'returns nil' do
        expect(gateway.parse_webhook_event(authorisation_payload.to_json, {})).to be_nil
      end
    end

    context 'when payment session is not found' do
      before do
        authorisation_payload['notificationItems'][0]['NotificationRequestItem']['additionalData']['checkoutSessionId'] = 'unknown'
      end

      it 'returns nil' do
        expect(gateway.parse_webhook_event(authorisation_payload.to_json, {})).to be_nil
      end
    end

    context 'with invalid HMAC signature' do
      before do
        allow(gateway).to receive(:valid_hmac?).and_return(false)
      end

      it 'raises WebhookSignatureError' do
        expect {
          gateway.parse_webhook_event(authorisation_payload.to_json, {})
        }.to raise_error(Spree::PaymentMethod::WebhookSignatureError)
      end
    end
  end
end
