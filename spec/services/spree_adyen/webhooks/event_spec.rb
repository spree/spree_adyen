require 'spec_helper'

RSpec.describe SpreeAdyen::Webhooks::Event do
  subject(:event) { described_class.new(event_data: event_data) }

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
              "checkoutSessionId": 'CS4FBB6F827EC53AC7',
              "paymentMethod": "mc",
              "checkout.cardAddedBrand": "**",
              "storedPaymentMethodId": "HF7Z59JSZZSBJWT5",
              "hmacSignature": "ZmFrZV9zaWduYXR1cmU="
            },
            "amount": {
              "currency": "EUR",
              "value": 100_00
            },
            "eventCode": "AUTHORISATION",
            "eventDate": "2025-07-04T12:59:19+02:00",
            "merchantAccountCode": "SpreeCommerceECOM",
            "merchantReference": "R123456789_12345_PX6H2G23",
            "operations": [
              "CANCEL",
              "CAPTURE",
              "REFUND"
            ],
            "paymentMethod": "mc",
            "pspReference": "123432123",
            "reason": "087969:0004:03/2030",
            "success": "true"
          }
        }
      ]
    }
  end

  describe '#order_number' do
    it 'returns the order number' do
      expect(event.order_number).to eq('R123456789')
    end
  end

  describe '#payment_method_id' do
    it 'returns the payment method id' do
      expect(event.payment_method_id).to eq('12345')
    end
  end

  describe '#amount' do
    it 'returns the amount' do
      expect(event.amount).to eq(Spree::Money.new(100, currency: 'EUR'))
      expect(event.amount.cents).to eq(100_00)
    end
  end
end