require 'spec_helper'

RSpec.describe Spree::PaymentMethod do
  let(:payment_method) { create(:adyen_gateway) }
  let(:other_payment_method) { create(:payment_method) }

  describe '#adyen?' do
    subject { payment_method.adyen? }

    it { is_expected.to be_truthy }

    context 'when the payment method is not an Adyen payment method' do
      let(:payment_method) { other_payment_method }

      it { is_expected.to be_falsey }
    end
  end

  describe 'scope' do
    subject { Spree::PaymentMethod.adyen }

    before do
      other_payment_method
    end

    it 'returns the Adyen payment methods' do
      expect(subject).to include(payment_method)
      expect(subject).not_to include(other_payment_method)
    end
  end
end