require 'spec_helper'

RSpec.describe Spree::PaymentSessions::Adyen, type: :model do
  let(:store) { Spree::Store.default }
  let(:gateway) do
    create(:adyen_gateway,
      stores: [store],
      preferred_api_key: 'secret',
      preferred_merchant_account: 'SpreeCommerceECOM',
      preferred_test_mode: true)
  end
  let(:order) { create(:order_with_line_items, store: store) }
  let(:payment_session) do
    described_class.create!(
      order: order,
      payment_method: gateway,
      amount: order.total,
      currency: order.currency,
      status: 'pending',
      external_id: 'CS_test_session_123',
      external_data: { 'session_data' => 'test', 'channel' => 'Web' }
    )
  end

  describe '#find_or_create_payment!' do
    it 'returns nil when not persisted' do
      session = described_class.new(order: order, payment_method: gateway)
      expect(session.find_or_create_payment!).to be_nil
    end

    it 'returns existing payment if present' do
      payment = create(:payment, order: order, payment_method: gateway, response_code: payment_session.external_id, amount: payment_session.amount)
      expect(payment_session.reload.find_or_create_payment!).to eq(payment)
    end

    it 'creates a new payment when none exists' do
      expect { payment_session.find_or_create_payment! }.to change(Spree::Payment, :count).by(1)

      payment = payment_session.find_or_create_payment!
      expect(payment.payment_method).to eq(gateway)
      expect(payment.response_code).to eq('CS_test_session_123')
      expect(payment.amount).to eq(payment_session.amount)
    end

    it 'accepts metadata argument without error' do
      expect { payment_session.find_or_create_payment!(charge_id: 'psp_123') }.to change(Spree::Payment, :count).by(1)
    end
  end
end
