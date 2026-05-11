require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSetupSessions::RequestPayloadPresenter do
  let(:store) { Spree::Store.default }
  let(:gateway) { create(:adyen_gateway, stores: [store]) }
  let(:customer) { create(:user, email: 'shopper@example.com', first_name: 'Jane', last_name: 'Roe') }
  let(:presenter) do
    described_class.new(
      customer: customer,
      merchant_account: 'SpreeCommerceECOM',
      payment_method: gateway,
      channel: 'Web',
      return_url: 'https://example.com/setup/return',
      currency: 'USD'
    )
  end

  describe '#to_h' do
    subject(:payload) { presenter.to_h }

    it 'sets amount.value to 0 (zero-auth tokenization)' do
      expect(payload[:amount]).to eq(value: 0, currency: 'USD')
    end

    it 'enables tokenization via storePaymentMethodMode and recurring params' do
      expect(payload[:storePaymentMethodMode]).to eq('enabled')
      expect(payload[:recurringProcessingModel]).to eq('UnscheduledCardOnFile')
      expect(payload[:shopperInteraction]).to eq('Ecommerce')
    end

    it 'builds a SETUP-prefixed reference scoped to the payment method' do
      expect(payload[:reference]).to match(/\ASETUP_#{gateway.id}_[0-9a-f]+\z/)
    end

    it 'embeds shopper details from the customer' do
      expect(payload[:shopperEmail]).to eq('shopper@example.com')
      expect(payload[:shopperReference]).to eq("customer_#{customer.id}")
      expect(payload[:shopperName]).to eq(firstName: 'Jane', lastName: 'Roe')
    end

    it 'tags metadata so webhooks can identify setup sessions' do
      expect(payload[:metadata]).to include(
        spree_payment_method_id: gateway.id,
        spree_setup_session: true
      )
    end

    it 'sets returnUrl, merchantAccount, and expiresAt' do
      expect(payload[:returnUrl]).to eq('https://example.com/setup/return')
      expect(payload[:merchantAccount]).to eq('SpreeCommerceECOM')
      expect(payload[:expiresAt]).to be_present
    end

    context 'with no currency override' do
      let(:presenter) do
        described_class.new(
          customer: customer,
          merchant_account: 'SpreeCommerceECOM',
          payment_method: gateway,
          channel: 'Web',
          return_url: 'https://example.com/setup/return'
        )
      end

      it 'defaults to USD' do
        expect(payload.dig(:amount, :currency)).to eq('USD')
      end
    end

    context 'with iOS channel' do
      let(:presenter) do
        described_class.new(
          customer: customer,
          merchant_account: 'SpreeCommerceECOM',
          payment_method: gateway,
          channel: 'iOS',
          return_url: 'https://example.com/setup/return'
        )
      end

      it 'blocks googlepay' do
        expect(payload[:channel]).to eq('iOS')
        expect(payload[:blockedPaymentMethods]).to eq(['googlepay'])
      end
    end
  end
end
