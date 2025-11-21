require 'spec_helper'

RSpec.describe Spree::Payment do
  describe '#capture!' do
    subject { payment.capture! }

    let(:payment) { create(:payment, state: 'pending', amount: 110, payment_method: payment_method) }

    context 'for the Adyen gateway' do
      let(:payment_method) { create(:adyen_gateway) }

      before do
        payment.update(response_code: 'ADYEN_PAYMENT_PSP_REFERENCE')
      end

      it 'requests a capture' do
        VCR.use_cassette("payment_api/captures/success") do
          subject
        end

        expect(payment.reload.state).to eq('capture_pending')
        expect(payment.capture_events.count).to eq(0)
      end

      context 'when the capture request was not successful' do
        it 'fails the payment' do
          VCR.use_cassette("payment_api/captures/failure") do
            expect { subject }.to raise_error(Spree::Core::GatewayError, 'Original pspReference required for this operation')
          end

          expect(payment.reload.state).to eq('failed')
        end
      end
    end

    context 'for other gateways' do
      let(:payment_method) { create(:credit_card_payment_method) }

      before do
        allow(payment).to receive(:request_capture!)
      end

      it 'captures the payment' do
        subject

        expect(payment).to_not have_received(:request_capture!)

        expect(payment.reload.state).to eq('completed')
        expect(payment.capture_events.count).to eq(1)
        expect(payment.capture_events.first.amount).to eq(110)
      end
    end
  end

  describe '#void_transaction!' do
    subject { payment.void_transaction! }

    let(:payment) { create(:payment, state: 'pending', amount: 110, payment_method: payment_method) }

    context 'for the Adyen gateway' do
      let(:payment_method) { create(:adyen_gateway) }

      before do
        payment.update(response_code: 'ADYEN_PAYMENT_PSP_REFERENCE')
      end

      it 'requests a void' do
        VCR.use_cassette("payment_api/voids/success") do
          subject
        end

        expect(payment.reload.state).to eq('void_pending')
      end
    end

    context 'for other gateways' do
      let(:payment_method) { create(:credit_card_payment_method) }

      before do
        allow(payment).to receive(:request_void!)
      end

      it 'voids the payment' do
        subject

        expect(payment).to_not have_received(:request_void!)
        expect(payment.reload.state).to eq('void')
      end
    end
  end
end
