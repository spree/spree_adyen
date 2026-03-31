require 'spec_helper'

RSpec.describe SpreeAdyen::Refunds::Retry do
  subject(:result) { described_class.call(refund: refund) }

  let(:gateway) do
    create(
      :adyen_gateway,
      stores: [Spree::Store.default],
      preferred_api_key: 'secret',
      preferred_merchant_account: 'SpreeCommerceECOM',
      preferred_test_mode: true
    )
  end

  let(:order) { create(:order, total: 10, number: 'R142767632') }
  let(:payment) { create(:payment, state: 'completed', order: order, payment_method: gateway, amount: 10.0, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
  let(:refund) { create(:refund, payment: payment, amount: 8.0, transaction_id: 'old_psp_reference') }

  before do
    refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, 'rejected')
    refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY, 'Insufficient in-process funds on account')
  end

  context 'when the refund is not rejected' do
    before do
      refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, 'submitted')
    end

    it 'returns failure' do
      expect(result).to be_failure
      expect(result.value).to eq('Refund is not rejected')
    end
  end

  context 'when the refund is successful' do
    it 'returns success' do
      VCR.use_cassette('payment_api/create_refund/success_partial') do
        expect(result).to be_success
        expect(result.value).to eq(refund)
      end
    end

    it 'updates the transaction_id' do
      VCR.use_cassette('payment_api/create_refund/success_partial') do
        result

        expect(refund.reload.transaction_id).to eq('ADYEN_PSP_REFERENCE')
      end
    end

    it 'resets the refund status to pending and clears the error message' do
      VCR.use_cassette('payment_api/create_refund/success_partial') do
        result

        refund.reload
        expect(refund.adyen_refund_status).to eq('pending')
        expect(refund.adyen_refund_error_message).to be_nil
      end
    end
  end

  context 'when the refund fails with a gateway error' do
    it 'returns failure with error message' do
      VCR.use_cassette('payment_api/create_refund/failure/invalid_amount') do
        expect(result).to be_failure
        expect(result.value).to include("Field 'amount' is not valid.")
      end
    end

    it 'does not update the transaction_id' do
      VCR.use_cassette('payment_api/create_refund/failure/invalid_amount') do
        result

        expect(refund.reload.transaction_id).to eq('old_psp_reference')
      end
    end

    it 'does not change the metafields' do
      VCR.use_cassette('payment_api/create_refund/failure/invalid_amount') do
        result

        expect(refund.reload.adyen_refund_status).to eq('rejected')
        expect(refund.adyen_refund_error_message).to eq('Insufficient in-process funds on account')
      end
    end
  end
end
