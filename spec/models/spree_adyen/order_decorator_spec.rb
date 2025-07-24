require 'spec_helper'

RSpec.describe SpreeAdyen::OrderDecorator do
  let(:order) { create(:order_with_line_items) }

  let(:invalid_price_sessions) do
    [
      create(:payment_session, :initial, :expired, order: order),
      create(:payment_session, :initial, order: order)
    ]
  end
  let(:invalid_currency_sessions) do
    [
      create(:payment_session, :initial, :expired, order: order),
      create(:payment_session, :initial, order: order)
    ]
  end

  before do
    create(:payment_session, :initial, order: order, amount: order.total_minus_store_credits, currency: order.currency)
    create(:payment_session, :pending, order: order, amount: order.total_minus_store_credits, currency: order.currency)
    create(:payment_session, :completed, order: order, amount: order.total_minus_store_credits, currency: order.currency)

    # to be soft deleted
    invalid_price_sessions.each do |session|
      session.update_attribute(:amount, order.total_minus_store_credits + 1)
    end
    invalid_currency_sessions.each do |session|
      session.update_attribute(:currency, 'PLN')
    end
  end

  describe '#outdate_payment_sessions' do
    subject(:outdate_payment_sessions) { order.outdate_payment_sessions }

    it 'removes outdated (with wrong amount or currency) payment sessions' do
      expect { outdate_payment_sessions }.to change { SpreeAdyen::PaymentSession.count }.by(-4)
    end
  end
end