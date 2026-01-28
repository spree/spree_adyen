require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSessionsController, type: :controller do
  routes { Spree::Core::Engine.routes }
  render_views

  let(:store) { Spree::Store.default }
  let(:order) { create(:order_with_line_items, store: store, state: :payment) }
  let(:adyen_gateway) { create(:adyen_gateway, stores: [store]) }
  let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }
  let(:payment_session) { create(:payment_session, order: order, amount: order.total, adyen_id: payment_session_id, payment_method: adyen_gateway) }
  let(:session_result) { 'resultData' }

  before do
    spree_routes = controller.spree
    allow(spree_routes).to receive(:checkout_complete_path) { |token| "/checkout/#{token}/complete" }
    allow(spree_routes).to receive(:cart_path).and_return('/cart')
    allow(spree_routes).to receive(:checkout_path) { |token| "/checkout/#{token}" }
  end

  describe 'GET #show' do
    context 'when payment session succeeds' do
      let(:complete_order_service) { instance_double(SpreeAdyen::Orders::Complete) }

      let(:send_request) do
        VCR.use_cassette('payment_session_results/success/completed') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
      end

      it 'completes the order and redirects to checkout complete' do
        expect { send_request }.to change(Spree::Payment, :count).by(1)
          .and change { order.reload.state }.to('complete')

        expect(response).to redirect_to("/checkout/#{order.token}/complete")
      end
    end

    context 'when order is already completed' do
      let(:order) { create(:completed_order_with_totals, store: store) }

      it 'redirects to checkout complete' do
        expect(controller).not_to receive(:track_checkout_completed)

        get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }

        expect(response).to redirect_to("/checkout/#{order.token}/complete")
      end
    end

    context 'when order is canceled' do
      let(:order) { create(:completed_order_with_totals, store: store, state: :canceled, canceled_at: Time.current) }

      it 'redirects to cart' do
        get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }

        expect(response).to redirect_to('/cart')
      end
    end

    context 'when payment session is canceled' do
      let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }

      it 'redirects to checkout' do
        VCR.use_cassette('payment_session_results/success/canceled') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
        expect(response).to redirect_to("/checkout/#{order.token}")
      end

      it 'voids the payment' do
        VCR.use_cassette('payment_session_results/success/canceled') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
        expect(order.payments.first.state).to eq('void')
      end
    end

    context 'when payment session is expired' do
      let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }

      it 'redirects to checkout' do
        VCR.use_cassette('payment_session_results/success/expired') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
        expect(response).to redirect_to("/checkout/#{order.token}")
      end

      it 'fails the payment' do
        VCR.use_cassette('payment_session_results/success/expired') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
        expect(order.payments.first.state).to eq('failed')
      end
    end

    context 'when payment session is refused' do
      let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }

      it 'redirects to checkout' do
        VCR.use_cassette('payment_session_results/success/refused') do
          get :show, params: { sessionId: payment_session.adyen_id, sessionResult: session_result }
        end
        expect(response).to redirect_to("/checkout/#{order.token}")
      end
    end
  end
end
