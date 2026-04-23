require 'spec_helper'

RSpec.describe SpreeAdyen::OrderDecorator do
  let(:order) { create(:order_with_line_items) }

  let(:invalid_price_sessions) do
    [
      create(:adyen_payment_session, :initial, :expired, order: order),
      create(:adyen_payment_session, :initial, order: order)
    ]
  end
  let(:invalid_currency_sessions) do
    [
      create(:adyen_payment_session, :initial, :expired, order: order),
      create(:adyen_payment_session, :initial, order: order)
    ]
  end

  before do
    create(:adyen_payment_session, :initial, order: order, amount: order.total_minus_store_credits, currency: order.currency)
    create(:adyen_payment_session, :pending, order: order, amount: order.total_minus_store_credits, currency: order.currency)
    create(:adyen_payment_session, :completed, order: order, amount: order.total_minus_store_credits, currency: order.currency)

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

    context 'when use_legacy_adyen_payment_sessions is enabled' do
      before { SpreeAdyen::Config[:use_legacy_adyen_payment_sessions] = true }

      after { SpreeAdyen::Config[:use_legacy_adyen_payment_sessions] = false }

      it 'removes outdated (with wrong amount or currency) payment sessions' do
        expect { outdate_payment_sessions }.to change { SpreeAdyen::PaymentSession.count }.by(-4)
      end
    end

    context 'when use_legacy_adyen_payment_sessions is disabled' do
      it 'does not remove any payment sessions' do
        expect { outdate_payment_sessions }.not_to change { SpreeAdyen::PaymentSession.count }
      end
    end
  end

  describe '#can_create_adyen_payment_session?' do
    incorrect_states = %w[cart delivery complete address canceled returned partially_canceled]
    correct_states = %w[confirm payment]

    incorrect_states.each do |state|
      it "returns false for #{state} state" do
        order.state = state
        expect(order.can_create_adyen_payment_session?).to be_falsey
      end
    end

    correct_states.each do |state|
      it "returns true for #{state} state" do
        order.state = state
        expect(order.can_create_adyen_payment_session?).to be_truthy
      end
    end
  end
end