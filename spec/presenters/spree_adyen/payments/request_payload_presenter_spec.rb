require 'spec_helper'

RSpec.describe SpreeAdyen::Payments::RequestPayloadPresenter do
  subject(:serializer) { described_class.new(source: source, amount_in_cents: amount, manual_capture: manual_capture, gateway_options: gateway_options) }

  let(:source) { create(:credit_card, gateway_payment_profile_id: '12345', payment_method: payment_method) }
  let(:gateway_options) { { order_id: 'R123456789-PX6H2G23' } }
  let(:amount) { 100 * 100 }
  let(:manual_capture) { false }

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
            integrator: 'Vendo Sp. z o.o.'
          },
          merchantApplication: {
            name: 'Community Edition',
            version: '0.0.1'
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

      context 'with manual capture' do
        let(:manual_capture) { true }

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
    end
  end
end
