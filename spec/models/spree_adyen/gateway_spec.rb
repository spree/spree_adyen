require 'spec_helper'

RSpec.describe SpreeAdyen::Gateway do
  subject(:gateway) do
    create(:adyen_gateway,
      stores: [store],
      preferred_api_key: 'secret',
      preferred_merchant_account: 'SpreeCommerceECOM',
      preferred_test_mode: test_mode,
      preferred_webhook_id: webhook_id,
      preferred_hmac_key: hmac_key
    )
  end
  let(:store) { Spree::Store.default }
  let(:amount) { 100 }
  let(:test_mode) { true }
  let(:webhook_id) { '1234567890' }
  let(:hmac_key) { '1234567890' }

  describe 'validations' do
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
              expect(gateway.errors.full_messages).to include(a_string_matching(/Preferred api key is invalid. Response: Adyen::AuthenticationError code:401/))
            end
          end
        end

        context 'without required permissions (403)' do
          it 'is invalid' do
            VCR.use_cassette('management_api/get_api_credential_details/failure_403') do
              expect(gateway).to be_invalid
              expect(gateway.errors.full_messages).to include(a_string_matching(/Preferred api key has insufficient permissions. Add missing roles to API credential. Response: Adyen::PermissionError code:403/))
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
      it 'returns proper (successful) ActiveMerchant::Billing::Response instance' do
        VCR.use_cassette('payment_session_results/success/completed') do
          expect(subject).to be_a(ActiveMerchant::Billing::Response)
          expect(subject.success?).to be_truthy
          expect(subject.authorization).to eq(payment_session_id)
        end
      end
    end

    context 'with invalid params' do
      let(:session_result) { 'invalid' }

      it 'returns proper (unsuccessful) ActiveMerchant::Billing::Response instance' do
        VCR.use_cassette('payment_session_results/failure') do
          expect(subject).to be_a(ActiveMerchant::Billing::Response)
          expect(subject.success?).to be_falsey
          expect(subject.message).to eq('ADYEN_PSP_REFERENCE - server could not process request')
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

  describe '#create_payment_session' do
    subject { gateway.create_payment_session(amount, order, channel, return_url) }

    let(:order) { create(:order_with_line_items) }
    let(:bill_address) { order.bill_address }
    let(:amount) { 100 }
    let(:channel) { 'Web' }
    let(:return_url) { 'http://www.example.com/adyen/payment_sessions/redirect' }
    let(:payment_session_id) { 'CS2BD6B9B093D32284D8EB223' }

    context 'with valid params' do
      it 'returns proper (successful) ActiveMerchant::Billing::Response instance' do
        VCR.use_cassette('payment_sessions/success') do
          expect(subject).to be_a(ActiveMerchant::Billing::Response)
          expect(subject.success?).to be_truthy
          expect(subject.authorization).to eq(payment_session_id)
        end
      end
    end

    context 'with invalid params' do
      before do
        allow(bill_address).to receive(:country_iso).and_return('INVALID')
      end

      it 'returns proper (unsuccessful) ActiveMerchant::Billing::Response instance' do
        VCR.use_cassette('payment_sessions/failure') do
          expect(subject).to be_a(ActiveMerchant::Billing::Response)
          expect(subject.success?).to be_falsey
          expect(subject.message).to eq("ADYEN_PSP_REFERENCE - Field 'countryCode' is not valid.")
        end
      end
    end
  end

  describe '#generate_client_key' do
    subject { gateway.generate_client_key }

    it 'returns proper (successful) ActiveMerchant::Billing::Response instance' do
      VCR.use_cassette('management_api/generate_client_key/success') do
        expect(subject).to be_a(ActiveMerchant::Billing::Response)
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
      let(:gateway) { create(:adyen_gateway, preferred_test_mode: false) }

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

    it 'returns proper (successful) ActiveMerchant::Billing::Response instance' do
      VCR.use_cassette('payment_api/payments/success') do
        expect(subject).to be_a(ActiveMerchant::Billing::Response)
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
          expect { subject }.to raise_error(Spree::Core::GatewayError, 'ADYEN_PSP_REFERENCE - Original pspReference required for this operation')
        end
      end
    end
  end

  describe '#credit' do
    subject { gateway.credit(amount_in_cents, payment.source, passed_response_code, {}) }

    let(:order) { create(:order, total: 10, number: 'R142767632') }
    let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
    let(:amount_in_cents) { 800 }
    let(:passed_response_code) { payment.response_code }

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

      it 'should return failure response' do
        VCR.use_cassette("payment_api/create_refund/failure/invalid_amount") do
          expect(subject.success?).to eq(false)
          expect(subject.message).to eq("ADYEN_PSP_REFERENCE - Field 'amount' is not valid.")
        end
      end
    end

    context 'when payment is not found' do
      let(:passed_response_code) { 'foobar' }

      it 'should return failure response' do
        expect(subject.success?).to eq(false)
        expect(subject.message).to eq("foobar - Payment not found")
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
end
