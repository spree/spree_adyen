require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSetupSessions::CreateSourceFromResult do
  let(:store) { Spree::Store.default }
  let(:gateway) { create(:adyen_gateway, stores: [store]) }
  let(:customer) { create(:user) }
  let(:setup_session) do
    Spree::PaymentSetupSessions::Adyen.create!(
      customer: customer,
      payment_method: gateway,
      status: 'pending',
      external_id: 'CS_SETUP_xyz'
    )
  end

  describe '#call' do
    context 'with a credit card brand and stored payment method id' do
      let(:response_params) do
        {
          'id' => 'CS_SETUP_xyz',
          'status' => 'completed',
          'additionalData' => {
            'paymentMethod' => 'mc',
            'tokenization.storedPaymentMethodId' => 'TOKEN_MC_123'
          }
        }
      end

      it 'creates a credit card source attributed to the customer' do
        source = described_class.new(setup_session: setup_session, response_params: response_params).call

        expect(source).to be_a(Spree::CreditCard)
        expect(source.gateway_payment_profile_id).to eq('TOKEN_MC_123')
        expect(source.cc_type).to eq('master')
        expect(source.user).to eq(customer)
        expect(source.payment_method).to eq(gateway)
      end

      it 'is idempotent — repeat calls reuse the existing source' do
        first = described_class.new(setup_session: setup_session, response_params: response_params).call
        second = described_class.new(setup_session: setup_session, response_params: response_params).call

        expect(first).to eq(second)
      end
    end

    context 'with recurring.recurringDetailReference fallback' do
      let(:response_params) do
        {
          'additionalData' => {
            'paymentMethod' => 'visa',
            'recurring.recurringDetailReference' => 'RECURRING_VISA_999'
          }
        }
      end

      it 'uses recurringDetailReference when tokenization.storedPaymentMethodId is missing' do
        source = described_class.new(setup_session: setup_session, response_params: response_params).call

        expect(source.gateway_payment_profile_id).to eq('RECURRING_VISA_999')
        expect(source.cc_type).to eq('visa')
      end
    end

    context 'with a non-credit-card payment method' do
      let(:response_params) do
        {
          'additionalData' => {
            'paymentMethod' => 'paypal',
            'tokenization.storedPaymentMethodId' => 'TOKEN_PAYPAL_500'
          }
        }
      end

      it 'creates an alternative source from the SOURCE_KLASS_MAP' do
        source = described_class.new(setup_session: setup_session, response_params: response_params).call

        expect(source).to be_a(SpreeAdyen::PaymentSources::Paypal)
        expect(source.gateway_payment_profile_id).to eq('TOKEN_PAYPAL_500')
        expect(source.user).to eq(customer)
      end
    end

    context 'when no stored payment method id is present' do
      let(:response_params) { { 'additionalData' => { 'paymentMethod' => 'mc' } } }

      it 'returns nil without creating a source' do
        expect {
          described_class.new(setup_session: setup_session, response_params: response_params).call
        }.not_to change(Spree::CreditCard, :count)
      end
    end
  end
end
