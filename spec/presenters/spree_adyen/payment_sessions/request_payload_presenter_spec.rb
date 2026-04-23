require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSessions::RequestPayloadPresenter do
  subject(:serializer) { described_class.new(**params) }

  let(:params) do
    {
      order: order,
      amount: amount,
      user: user,
      merchant_account: merchant_account,
      payment_method: payment_method,
      channel: channel,
      return_url: return_url
    }
  end

  let(:order) { create(:order, bill_address: address, ship_address: address, number: 'R123456789', total: 100, user: user, currency: 'USD', line_items: [line_item]) }
  let(:user) { create(:user, email: 'test@example.com', first_name: 'John', last_name: 'Doe') }
  let(:amount) { 100 }
  let(:payment_method) { create(:adyen_gateway) }
  let(:merchant_account) { 'SpreeCommerceECOM' }
  let(:line_items) { [line_item] }
  let(:line_item) { build(:line_item, price: 100, variant: variant) }
  let(:variant) { create(:variant) }
  let(:address) { create(:address, firstname: 'John', lastname: 'Doe') }
  let(:channel) { 'Web' }
  let(:return_url) { 'http://www.example.com/adyen/payment_sessions/redirect' }
  let(:auto_capture) { true }

  before do
    payment_method.update(auto_capture: auto_capture)

    allow(Spree).to receive(:version).and_return('42.0.0')
    allow(SpreeAdyen).to receive(:version).and_return('0.0.1')
  end

  context 'with valid params' do
    let(:expected_payload) do
      {
        metadata: {
          spree_payment_method_id: payment_method.id,
          spree_order_id: order.number
        },
        amount: {
          value: amount * 100,
          currency: order.currency
        },
        returnUrl: "http://www.example.com/adyen/payment_sessions/redirect",
        recurringProcessingModel: "UnscheduledCardOnFile",
        shopperInteraction: "Ecommerce",
        storePaymentMethodMode: "enabled",
        reference: expected_reference,
        countryCode: address.country_iso,
        lineItems: [
          {
            id: line_item.id,
            sku: line_item.sku,
            quantity: line_item.quantity,
            description: line_item.name,
            amountExcludingTax: 10000,
            amountIncludingTax: 10000
          }
        ],
        merchantAccount: merchant_account,
        merchantOrderReference: 'R123456789',
        expiresAt: 60.minutes.from_now.iso8601,
        channel: 'Web',
        shopperName: {
          firstName: 'John',
          lastName: 'Doe'
        },
        shopperEmail: order.email,
        shopperReference: "customer_#{user.id}",
        applicationInfo: {
          externalPlatform: {
            name: 'Spree Commerce',
            version: '42.0.0',
            integrator: 'Vendo Sp. z o.o.'
          },
          merchantApplication: {
            name: 'Community Edition',
            version: '0.0.1'
          }
        }
      }
    end

    let(:expected_reference) { "R123456789_#{payment_method.id}_1" }

    describe '#to_h' do
      subject(:payload) { serializer.to_h }

      it 'returns a valid payload' do
        expect(payload).to eq(expected_payload)
      end

      context 'with manual capture' do
        let(:auto_capture) { false }

        let(:expected_payload_with_manual_capture) do
          expected_payload.merge(
            additionalData: {
              manualCapture: true
            }
          )
        end

        it 'returns a valid payload' do
          expect(payload).to eq(expected_payload_with_manual_capture)
        end
      end

      context 'without channel' do
        let(:channel) { nil }

        it 'does not include channel' do
          expect(payload.keys).not_to include(:channel)
        end
      end

      context 'with iOS channel' do
        let(:channel) { 'iOS' }

        it 'blocks google pay' do
          expect(payload).to include(blockedPaymentMethods: ['googlepay'])
        end
      end

      context 'with Android channel' do
        let(:channel) { 'Android' }

        it 'blocks apple pay' do
          expect(payload).to include(blockedPaymentMethods: ['applepay'])
        end
      end

      context 'when payment session already exists' do
        let(:expected_reference) { "R123456789_#{payment_method.id}_2" }

        before do
          Spree::PaymentSessions::Adyen.create!(
            order: order,
            payment_method: payment_method,
            amount: order.total_minus_store_credits,
            currency: order.currency,
            status: 'pending',
            external_id: 'CS4FBB6F827EC53AC7',
            deleted_at: 1.day.ago
          )
        end

        it 'returns a valid payload' do
          expect(payload).to eq(expected_payload)
        end
      end

      context 'when payment session already exists (legacy)' do
        let(:expected_reference) { "R123456789_#{payment_method.id}_2" }

        before do
          SpreeAdyen::Config[:use_legacy_adyen_payment_sessions] = true
          create(:adyen_payment_session, deleted_at: 1.day.ago, amount: order.total_minus_store_credits, order: order, adyen_id: 'CS4FBB6F827EC53AC7')
        end

        after { SpreeAdyen::Config[:use_legacy_adyen_payment_sessions] = false }

        it 'returns a valid payload' do
          expect(payload).to eq(expected_payload)
        end
      end

      context 'without address' do
        let(:address) { nil }

        it 'does not raise an error' do
          expect { payload }.not_to raise_error
        end
      end
    end
  end
end
