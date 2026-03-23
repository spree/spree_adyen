require 'spec_helper'

RSpec.describe SpreeAdyen::Webhooks::Actions::CreateSource do
  subject(:service) { described_class.new(event: event, payment_method: payment_method, user: user).call }

  let(:event) { SpreeAdyen::Webhooks::Event.new(event_data: event_data) }

  let(:payment_method) { create(:adyen_gateway) }
  let(:user) { create(:user) }

  context 'with credit card payment method' do
    let(:event_data) do
      {
        "live": "false",
        "notificationItems": [
          {
            "NotificationRequestItem": {
              "additionalData": {
                "expiryDate": "03/2030",
                "authCode": '12345',
                "cardSummary": "0004",
                "isCardCommercial": "something",
                "threeds2.cardEnrolled": "false",
                "paymentMethod": payment_method_reference,
                "checkout.cardAddedBrand": "**",
                "storedPaymentMethodId": "HF7Z59JSZZSBJWT5",
                "hmacSignature": "ZmFrZV9zaWduYXR1cmU="
              },
              "amount": {
                "currency": "EUR",
                "value": 1000
              },
              "eventCode": "AUTHORISATION",
              "eventDate": "2025-07-04T12:59:19+02:00",
              "merchantAccountCode": "SpreeCommerceECOM",
              "merchantReference": "d236555b-14d8-48cc-b53c-6a8788c2bb1e",
              "operations": [
                "CANCEL",
                "CAPTURE",
                "REFUND"
              ],
              "paymentMethod": payment_method_reference,
              "pspReference": "123432123",
              "reason": "087969:0004:03/2030",
              "success": "true"
            }
          }
        ]
      }
    end

    context 'with mastercard credit card' do
      let(:payment_method_reference) { 'mc' }

      it 'creates a credit card' do
        expect { service }.to change(Spree::CreditCard, :count).by(1)
      end

      it 'creates a mastercard credit card with the correct attributes' do
        expect { service }.to change(Spree::CreditCard, :count).by(1)
        expect(Spree::CreditCard.last.gateway_payment_profile_id).to eq('HF7Z59JSZZSBJWT5')
        expect(Spree::CreditCard.last.month).to eq(3)
        expect(Spree::CreditCard.last.cc_type).to eq('master')
        expect(Spree::CreditCard.last.year).to eq(2030)
      end

      context 'with jcb credit card' do
        let(:payment_method_reference) { 'jcb' }

        it 'creates a credit card' do
          expect { service }.to change(Spree::CreditCard, :count).by(1)
        end

        it 'creates a mastercard credit card with the correct attributes' do
          expect { service }.to change(Spree::CreditCard, :count).by(1)
          expect(Spree::CreditCard.last.gateway_payment_profile_id).to eq('HF7Z59JSZZSBJWT5')
          expect(Spree::CreditCard.last.month).to eq(3)
          expect(Spree::CreditCard.last.cc_type).to eq('jcb')
          expect(Spree::CreditCard.last.year).to eq(2030)
        end
      end
    end
  end

  context 'when the payment method is not a credit card' do
    let(:event_data) do
      {
        "live": "false",
        "notificationItems": [
          {
            "NotificationRequestItem": {
              "additionalData": additional_data,
              "amount": {
                "currency": "EUR",
                "value": 1000
              },
              "eventCode": "AUTHORISATION",
              "eventDate": "2025-07-04T12:59:19+02:00",
              "merchantAccountCode": "SpreeCommerceECOM",
              "merchantReference": "d236555b-14d8-48cc-b53c-6a8788c2bb1e",
              "operations": [
                "CANCEL",
                "CAPTURE",
                "REFUND"
              ],
              "paymentMethod": payment_method_reference,
              "pspReference": "123432123",
              "reason": "null",
              "success": "true"
            }
          }
        ]
      }
    end
    let(:additional_data) do
      {
        "recurring.recurringDetailReference": "CWPPBJZ7VV7257X3",
        "hmacSignature": "ZmFrZV9zaWduYXR1cmU="
      }
    end

    context 'for a known payment method' do
      let(:payment_method_reference) { 'klarna' }

      it 'creates a custom payment source' do
        expect { service }.to change(SpreeAdyen::PaymentSources::Klarna, :count).by(1)
      end

      it 'sets gateway_payment_profile_id from recurring.recurringDetailReference' do
        service
        expect(SpreeAdyen::PaymentSources::Klarna.last.gateway_payment_profile_id).to eq('CWPPBJZ7VV7257X3')
      end

      context 'when a source with the same token already exists' do
        before { described_class.new(event: event, payment_method: payment_method, user: user).call }

        it 'reuses the existing source' do
          expect { described_class.new(event: event, payment_method: payment_method, user: user).call }.not_to change(SpreeAdyen::PaymentSources::Klarna, :count)
        end
      end
    end

    context 'for an unknown payment method' do
      let(:payment_method_reference) { 'unknown' }

      it 'creates a custom payment source' do
        expect { service }.to change(SpreeAdyen::PaymentSources::Unknown, :count).by(1)
      end
    end

    context 'when no stored payment method id is present' do
      let(:payment_method_reference) { 'ideal' }
      let(:additional_data) { { "hmacSignature": "ZmFrZV9zaWduYXR1cmU=" } }

      it 'falls back to pspReference as gateway_payment_profile_id' do
        service
        expect(SpreeAdyen::PaymentSources::Ideal.last.gateway_payment_profile_id).to eq('123432123')
      end
    end

    context 'when stored payment method id is a blank string' do
      let(:payment_method_reference) { 'ideal' }
      let(:additional_data) do
        {
          "recurring.recurringDetailReference": "",
          "hmacSignature": "ZmFrZV9zaWduYXR1cmU="
        }
      end

      it 'falls back to pspReference as gateway_payment_profile_id' do
        service
        expect(SpreeAdyen::PaymentSources::Ideal.last.gateway_payment_profile_id).to eq('123432123')
      end
    end
  end
end
