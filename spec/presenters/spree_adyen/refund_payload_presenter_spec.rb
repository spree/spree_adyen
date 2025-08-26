require 'spec_helper'

RSpec.describe SpreeAdyen::RefundPayloadPresenter do
  subject(:serializer) { described_class.new(**params) }

  let(:params) do
    {
      amount_in_cents: amount,
      currency: currency,
      payment_method: payment_method,
      payment: payment
    }
  end

  let(:amount) { 100_00 }
  let(:currency) { 'USD' }
  let(:payment_method) { create(:adyen_gateway, preferred_merchant_account: 'SpreeCommerceECOM') }
  let(:payment) { create(:payment, amount: 100.00, payment_method: payment_method, order: order, response_code: '123456789') }
  let(:order) { create(:order_with_line_items, number: 'R123456789', total: 100, user: user, currency: 'USD') }
  let(:user) { create(:user) }

  before do
    allow(Spree).to receive(:version).and_return('42.0.0')
  end

  context 'with valid params' do
    let(:expected_payload) do
      {
        amount: {
          value: amount,
          currency: currency
        },
        reference: "R123456789_#{payment_method.id}_#{payment.response_code}_refund",
        merchantAccount: payment_method.preferred_merchant_account,
        applicationInfo: {
          externalPlatform: {
            name: 'Spree Commerce',
            version: '42.0.0',
            integrator: 'Spree Adyen'
          }
        }
      }
    end

    describe '#to_h' do
      subject(:payload) { serializer.to_h }

      it 'returns the correct payload' do
        expect(payload).to eq(expected_payload)
      end
    end
  end
end