require 'spec_helper'

RSpec.describe SpreeAdyen::Gateway::PaymentSetupSessions do
  let(:store) { Spree::Store.default }
  let(:gateway) do
    create(:adyen_gateway,
      stores: [store],
      preferred_api_key: ENV.fetch('ADYEN_TEST_API_KEY', 'secret'),
      preferred_merchant_account: ENV.fetch('ADYEN_TEST_MERCHANT_ACCOUNT', 'SpreeCommerceECOM'),
      preferred_test_mode: true)
  end
  let(:customer) { create(:user, email: 'setup-shopper@example.com', first_name: 'Setup', last_name: 'Shopper') }

  describe '#setup_session_supported?' do
    it 'is true' do
      expect(gateway.setup_session_supported?).to be(true)
    end
  end

  describe '#payment_setup_session_class' do
    it 'returns the Adyen STI class' do
      expect(gateway.payment_setup_session_class).to eq(Spree::PaymentSetupSessions::Adyen)
    end
  end

  describe '#create_payment_setup_session' do
    it 'creates a zero-auth tokenization session via the Adyen Sessions API' do
      VCR.use_cassette('payment_setup_sessions/create/success') do
        setup_session = gateway.create_payment_setup_session(customer: customer)

        expect(setup_session).to be_persisted
        expect(setup_session.payment_method).to eq(gateway)
        expect(setup_session.customer).to eq(customer)
        expect(setup_session.status).to eq('pending')
        expect(setup_session.external_id).to be_present
        expect(setup_session.session_data).to be_present
        expect(setup_session.external_data['shopper_reference']).to eq("customer_#{customer.id}")
      end
    end

    it 'accepts a custom channel and return_url via external_data' do
      VCR.use_cassette('payment_setup_sessions/create/success_with_ios_channel') do
        setup_session = gateway.create_payment_setup_session(
          customer: customer,
          external_data: { channel: 'iOS', return_url: 'myapp://adyen/return' }
        )

        expect(setup_session.channel).to eq('iOS')
        expect(setup_session.return_url).to eq('myapp://adyen/return')
      end
    end
  end

  describe '#complete_payment_setup_session' do
    let!(:setup_session) do
      Spree::PaymentSetupSessions::Adyen.create!(
        customer: customer,
        payment_method: gateway,
        status: 'pending',
        external_id: 'CS_SETUP_FAKE_ID',
        external_data: { 'session_data' => 'data-blob', 'channel' => 'Web' }
      )
    end

    context 'with neither session_result nor redirect_result' do
      it 'raises a gateway error' do
        expect {
          gateway.complete_payment_setup_session(setup_session: setup_session, params: {})
        }.to raise_error(Spree::Core::GatewayError, 'session_result or redirect_result is required')
      end
    end

    # Note: session_result and redirect_result paths require a real session that the Drop-in
    # browser flow completed. They are exercised end-to-end in storefront integration tests.
    # Unit coverage for the source-creation logic lives in
    # spec/services/spree_adyen/payment_setup_sessions/create_source_from_result_spec.rb.
  end
end
