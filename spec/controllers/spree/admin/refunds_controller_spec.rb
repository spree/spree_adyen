require 'spec_helper'

RSpec.describe Spree::Admin::RefundsController, type: :controller do
  stub_authorization!
  render_views

  let(:user) { create(:admin_user) }

  before do
    allow(controller).to receive(:current_ability).and_return(Spree.ability_class.new(user))
  end

  let(:order) { create(:completed_order_with_totals, number: 'R142767632') }
  let(:payment_method) do
    create(:adyen_gateway,
      stores: [Spree::Store.default],
      preferred_api_key: 'secret',
      preferred_merchant_account: 'SpreeCommerceECOM',
      preferred_test_mode: true
    )
  end
  let(:payment) { create(:payment, state: 'completed', amount: 20.0, order: order, payment_method: payment_method, response_code: 'ADYEN_PAYMENT_PSP_REFERENCE') }
  let!(:refund) { create(:refund, payment: payment, amount: 8.0, transaction_id: 'old_psp_reference') }

  before do
    refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_METAFIELD_KEY, SpreeAdyen::RefundDecorator::ADYEN_REFUND_STATUS_REJECTED)
    refund.set_metafield(SpreeAdyen::RefundDecorator::ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY, 'Insufficient in-process funds on account')
  end

  describe 'PUT #retry' do
    subject { put :retry, params: { order_id: order.to_param, payment_id: payment.to_param, id: refund.to_param } }

    context 'when the retry is successful' do
      it 'redirects to the order page with a success flash' do
        VCR.use_cassette('payment_api/create_refund/success_partial') do
          subject

          expect(response).to redirect_to spree.edit_admin_order_path(order)
          expect(flash[:success]).to eq(Spree.t(:refund_retry_submitted))
        end
      end

      it 'updates the refund' do
        VCR.use_cassette('payment_api/create_refund/success_partial') do
          subject

          refund.reload
          expect(refund.transaction_id).to eq('ADYEN_PSP_REFERENCE')
          expect(refund.adyen_refund_status).to eq('pending')
          expect(refund.adyen_refund_error_message).to be_nil
        end
      end
    end

    context 'when the retry fails' do
      it 'redirects to the order page with an error flash' do
        VCR.use_cassette('payment_api/create_refund/failure/invalid_amount') do
          subject

          expect(response).to redirect_to spree.edit_admin_order_path(order)
          expect(flash[:error]).to include("Field 'amount' is not valid.")
        end
      end
    end
  end
end
