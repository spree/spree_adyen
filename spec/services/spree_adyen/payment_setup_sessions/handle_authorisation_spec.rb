require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSetupSessions::HandleAuthorisation do
  let(:store) { Spree::Store.default }
  let(:gateway) { create(:adyen_gateway, stores: [store]) }
  let(:customer) { create(:user) }
  let(:setup_session) do
    Spree::PaymentSetupSessions::Adyen.create!(
      customer: customer,
      payment_method: gateway,
      status: 'pending',
      external_id: 'CS_SETUP_xyz'
    )
  end

  def build_event(success:, payment_method_reference: 'mc', stored_id: 'TOKEN_999', card_summary: '4242', expiry: '03/2030')
    SpreeAdyen::Webhooks::Event.new(event_data: {
      'notificationItems' => [{
        'NotificationRequestItem' => {
          'eventCode' => 'AUTHORISATION',
          'success' => success ? 'true' : 'false',
          'pspReference' => 'PSP_AUTH_111',
          'merchantReference' => "SETUP_#{gateway.id}_abc123",
          'amount' => { 'value' => 0, 'currency' => 'USD' },
          'paymentMethod' => payment_method_reference,
          'additionalData' => {
            'checkoutSessionId' => setup_session.external_id,
            'tokenization.storedPaymentMethodId' => stored_id,
            'cardSummary' => card_summary,
            'expiryDate' => expiry
          }
        }
      }]
    })
  end

  describe '#call' do
    context 'with a successful AUTHORISATION event' do
      it 'creates a credit card source from the event card details' do
        described_class.new(setup_session: setup_session, event: build_event(success: true)).call

        setup_session.reload
        expect(setup_session.payment_source).to be_a(Spree::CreditCard)
        expect(setup_session.payment_source.gateway_payment_profile_id).to eq('TOKEN_999')
        expect(setup_session.payment_source.cc_type).to eq('master')
        expect(setup_session.payment_source.last_digits).to eq('4242')
        expect(setup_session.payment_source.month).to eq(3)
        expect(setup_session.payment_source.year).to eq(2030)
        expect(setup_session.payment_source.user).to eq(customer)
      end

      it 'transitions the setup session to completed' do
        described_class.new(setup_session: setup_session, event: build_event(success: true)).call

        expect(setup_session.reload.status).to eq('completed')
      end

      it 'is idempotent — repeat calls do not duplicate the source' do
        expect {
          2.times { described_class.new(setup_session: setup_session, event: build_event(success: true)).call }
        }.to change(Spree::CreditCard, :count).by(1)
      end

      it 'returns the setup session unchanged when already completed' do
        setup_session.update!(status: 'completed')
        expect {
          described_class.new(setup_session: setup_session, event: build_event(success: true)).call
        }.not_to change(Spree::CreditCard, :count)
      end
    end

    context 'with a failed AUTHORISATION event' do
      it 'fails the setup session and does not create a source' do
        expect {
          described_class.new(setup_session: setup_session, event: build_event(success: false)).call
        }.not_to change(Spree::CreditCard, :count)

        expect(setup_session.reload.status).to eq('failed')
      end
    end
  end
end
