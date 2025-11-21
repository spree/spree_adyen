require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSessions::ProcessWithResult do
  subject(:service) { described_class.new(payment_session: payment_session, session_result: session_result).call }

  let(:payment_session) { create(:payment_session, adyen_id: 'CS4FBB6F827EC53AC7', status: 'initial') }
  let(:session_result) { 'resultData' }

  context 'when payment is completed' do
    it 'updates the payment session status' do
      VCR.use_cassette('payment_session_results/success/completed') do
        expect { service }.to change { payment_session.reload.status }.to('completed')
      end
    end

    context 'when void payment exists for other payment session' do
      let!(:void_payment) { create(:payment, order: payment_session.order, state: 'void') }

      it 'creates a new payment with completed status' do
        VCR.use_cassette('payment_session_results/success/completed') do
          expect { service }.to change(Spree::Payment, :count).by(1)

          expect(payment_session.order.payments).to be_present
          expect(payment_session.order.payments.last.state).to eq('completed')
        end
      end
    end

    it 'creates a payment with completed status' do
      VCR.use_cassette('payment_session_results/success/completed') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('completed')
      end
    end
  end

  context 'when payment is not automatically captured' do
    before do
      payment_session.payment_method.update(auto_capture: false)
    end

    it 'completed the payment session' do
      VCR.use_cassette('payment_session_results/success/completed') do
        expect { service }.to change(payment_session.reload, :status).to('completed')
      end
    end

    it 'creates a payment with pending status' do
      VCR.use_cassette('payment_session_results/success/completed') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('pending')
      end
    end
  end

  context 'when payment is refused' do
    it 'updates the payment session status' do
      VCR.use_cassette('payment_session_results/success/refused') do
        expect { service }.to change { payment_session.reload.status }.to('refused')
      end
    end

    it 'creates a payment with refused status' do
      VCR.use_cassette('payment_session_results/success/refused') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('failed')
      end
    end
  end

  context 'when payment is canceled' do
    it 'updates the payment session status' do
      VCR.use_cassette('payment_session_results/success/canceled') do
        expect { service }.to change(payment_session.reload, :status).to('canceled')
      end
    end

    it 'creates a payment with refused status' do
      VCR.use_cassette('payment_session_results/success/canceled') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('void')
      end
    end
  end

  context 'when payment is still pending (async payment)' do
    it 'updates the payment session status' do
      VCR.use_cassette('payment_session_results/success/payment_pending') do
        expect { service }.to change(payment_session.reload, :status).to('pending')
      end
    end

    it 'creates a payment with processing status' do
      VCR.use_cassette('payment_session_results/success/payment_pending') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('processing')
      end
    end
  end

  context 'when payment is expired' do
    it 'updates the payment session status' do
      VCR.use_cassette('payment_session_results/success/expired') do
        expect { service }.to change(payment_session.reload, :status).to('refused')
      end
    end

    it 'creates a payment with failed status' do
      VCR.use_cassette('payment_session_results/success/expired') do
        expect { service }.to change(Spree::Payment, :count).by(1)

        expect(payment_session.order.payments).to be_present
        expect(payment_session.order.payments.last.state).to eq('failed')
      end
    end
  end

  context 'when payment is in other state (should not according to adyen docs but...)' do
    it 'raises an error' do
      VCR.use_cassette('payment_session_results/success/other_state') do
        expect(Rails.error).to receive(:unexpected).with('Unexpected payment status', context: { order_id: payment_session.order.id, status: 'unknown' }, source: 'spree_adyen')

        subject
      end
    end
  end
end
