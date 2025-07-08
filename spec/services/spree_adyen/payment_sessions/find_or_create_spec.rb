require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSessions::FindOrCreate do
  subject(:service) { described_class.new(order: order, user: user, amount: amount, payment_method: payment_method).call }

  let(:order) { create(:order) }
  let(:user) { create(:user) }
  let(:amount) { 100 }
  let(:payment_method) { create(:adyen_gateway) }

  let(:existing_payment_session) do
    create(:payment_session,
      order: payment_order,
      status: payment_status,
      expires_at: 1.hour.from_now,
      user: payment_user,
      amount: payment_amount,
      payment_method: payment_payment_method
    )
  end

  before do
    # we use expires_at from the cassette, so we need to freeze the time
    Timecop.freeze('2025-07-07T0:00:00+02:00')
  end

  after do
    Timecop.return
  end

  context 'when payment session does not exist' do
    it 'creates a payment session' do
      VCR.use_cassette('payment_sessions/success') do
        expect { service }.to change(SpreeAdyen::PaymentSession, :count).by(1)
      end
    end
  end

  context 'when payment session exists' do
    let(:payment_status) { 'initial' }
    let(:payment_order) { order }
    let(:payment_user) { user }
    let(:payment_amount) { amount }
    let(:payment_payment_method) { payment_method }

    context 'when payment session is valid for the order' do
      before { existing_payment_session }

      it 'returns the existing payment session' do
        expect { subject }.to_not change(SpreeAdyen::PaymentSession, :count)
        expect(subject).to eq(existing_payment_session)
      end
    end

    context 'when payment session is expired' do
      before { Timecop.freeze(1.day.ago) { existing_payment_session } }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end

    context 'when payment session is not pending (for example completed)' do
      before { existing_payment_session }
      
      let(:payment_status) { 'completed' }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end

    context 'when payment session is for a different payment method' do
      before { existing_payment_session }
      
      let(:payment_payment_method) { create(:payment_method) }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end

    context 'when payment session is for a different user' do
      before { existing_payment_session }
      
      let(:payment_user) { create(:user) }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end

    context 'when payment session is for a different order' do
      before { existing_payment_session }
      
      let(:payment_order) { create(:order) }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end

    context 'when payment session is for a different amount' do
      before { existing_payment_session }
      
      let(:payment_amount) { 200 }

      it 'creates a new payment session' do
        VCR.use_cassette('payment_sessions/success') do
          expect { subject }.to change(SpreeAdyen::PaymentSession, :count).by(1)
        end
      end
    end
  end
end 