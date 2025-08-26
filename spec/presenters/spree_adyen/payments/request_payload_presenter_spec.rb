require 'spec_helper'

RSpec.describe SpreeAdyen::Payments::RequestPayloadPresenter do
  subject(:serializer) { described_class.new(source: source, amount_in_cents: amount, gateway_options: gateway_options) }

  let(:source) { create(:credit_card, gateway_payment_profile_id: '12345', payment_method: payment_method) }
  let(:gateway_options) { { order_id: 'R123456789-PX6H2G23' } }
  let(:amount) { 100 * 100 }

  before do
    create(:payment,
      number: 'PX6H2G23',
      order: order,
      payment_method: payment_method,
      source: source,
      amount: 100
    )
  end

  let(:order) { create(:order_with_line_items, number: 'R123456789', total: 100, user: user, currency: 'USD') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:adyen_gateway, preferred_merchant_account: 'SpreeCommerceECOM') }

  before do
    allow(Spree).to receive(:version).and_return('42.0.0')
  end

  context 'with valid params' do
    let(:expected_payload) do
      {
        metadata: {
          spree_payment_method_id: payment_method.id,
          spree_order_id: order.number
        },
        amount: {
          value: amount,
          currency: order.currency
        },
        shopperInteraction: "ContAuth",
        reference: expected_reference,
        recurringProcessingModel: "UnscheduledCardOnFile",
        merchantAccount: 'SpreeCommerceECOM',
        paymentMethod: {
          storedPaymentMethodId: '12345',
          type: 'scheme'
        },
        shopperReference: "customer_#{user.id}",
        applicationInfo: {
          externalPlatform: {
            name: 'Spree Commerce',
            version: '42.0.0',
            integrator: 'Spree Adyen'
          }
        }
      }
    end

    let(:expected_reference) { "R123456789_#{payment_method.id}_PX6H2G23" }

    describe '#to_h' do
      subject(:payload) { serializer.to_h }

      it 'returns a valid payload' do
        expect(payload).to eq(expected_payload)
      end
    end
  end
end