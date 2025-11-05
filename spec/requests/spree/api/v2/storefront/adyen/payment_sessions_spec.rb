require 'spec_helper'

RSpec.describe 'API V2 Storefront Adyen Payment Sessions', type: :request do
  let(:store) { Spree::Store.default }
  let(:user) { create(:user) }
  let(:order) { create(:order_with_line_items, user: nil, store: store, state: :payment, total: 100) }
  let!(:adyen_gateway) { create(:adyen_gateway, stores: [store], preferred_client_key: 'test_client_key') }
  let(:order_token) { order.token }

  let(:headers) {
    {
      'X-Spree-Order-Token' => order_token
    }
  }

  before do
    # Freeze time to match VCR cassette expiration dates
    Timecop.freeze('2025-08-14T16:00:00+02:00')
  end

  after do
    Timecop.return
  end

  describe 'POST /api/v2/storefront/adyen/payment_sessions' do
    subject(:post_request) { post url, params: params, headers: headers }

    let(:url) { '/api/v2/storefront/adyen/payment_sessions' }
    let(:amount) { order.total_minus_store_credits }
    let(:params) do
      {
        payment_session: {
          amount: amount
        }
      }
    end

    context 'with valid headers' do
      context 'with valid params' do
        context 'with channel' do
          let(:params) do
            {
              payment_session: {
                amount: amount,
                channel: 'iOS'
              }
            }
          end

          it 'creates a payment session successfully' do
            VCR.use_cassette('payment_sessions/success_with_ios_channel') do
              expect { post_request }.to change(SpreeAdyen::PaymentSession, :count).by(1)

              expect(response).to have_http_status(:ok)

              json_data = json_response['data']
              expect(json_data['attributes']['channel']).to eq('iOS')
            end
          end
        end

        context 'with return_url' do
          let(:params) do
            {
              payment_session: {
                amount: amount,
                return_url: 'http://valid-url.com/redirect'
              }
            }
          end

          it 'creates a payment session successfully' do
            VCR.use_cassette('payment_sessions/success_with_return_url') do
              expect { post_request }.to change(SpreeAdyen::PaymentSession, :count).by(1)

              expect(response).to have_http_status(:ok)

              json_data = json_response['data']
              expect(json_data['attributes']['return_url']).to eq('http://valid-url.com/redirect')
            end
          end
        end

        context 'without optional params' do
          it 'creates a payment session successfully' do
            VCR.use_cassette('payment_sessions/success_without_optional_params') do
              expect { post_request }.to change(SpreeAdyen::PaymentSession, :count).by(1)

              expect(response).to have_http_status(:ok)

              json_data = json_response['data']
              expect(json_data['type']).to eq('adyen_payment_session')
              expect(json_data['attributes']['amount']).to eq(amount.to_f.to_s)
              expect(json_data['attributes']['status']).to eq('initial')
              expect(json_data['attributes']['adyen_id']).to be_present
              expect(json_data['attributes']['client_key']).to eq('test_client_key')
              expect(json_data['attributes']['adyen_data']).to be_present
              expect(json_data['attributes']['channel']).to eq('Web') # default channel
              expect(json_data['attributes']['return_url']).to eq('http://www.example.com/adyen/payment_sessions/redirect') # default channel

              # Verify relationships
              expect(json_data['relationships']['order']['data']['id']).to eq(order.id.to_s)
              expect(json_data['relationships']['payment_method']['data']['id']).to eq(adyen_gateway.id.to_s)
            end
          end
        end
      end

      context 'with invalid amount' do
        let(:params) do
          {
            payment_session: {
              amount: 'invalid'
            }
          }
        end

        it 'returns unprocessable entity error' do
          VCR.use_cassette('payment_sessions/failure') do
            post_request

            expect(response).to have_http_status(:unprocessable_content)
            expect(json_response['errors']).to eq(
              'adyen_id' => ["can't be blank"],
              'adyen_data' => ["can't be blank"],
              'expires_at' => ["can't be blank"],
              'amount' => ["is not a number"]
            )
          end
        end
      end

      context 'with invalid channel' do
        let(:params) do
          {
            payment_session: {
              amount: amount,
              channel: 'invalid'
            }
          }
        end

        it 'returns unprocessable entity error' do
          VCR.use_cassette('payment_sessions/failure') do
            post_request

            expect(response).to have_http_status(:unprocessable_content)
            expect(json_response['errors']).to eq(
              'adyen_id' => ["can't be blank"],
              'adyen_data' => ["can't be blank"],
              'expires_at' => ["can't be blank"],
              'channel' => ["is not included in the list"]
            )
          end
        end
      end

      context 'when amount is greater than order total' do
        let(:amount) { order.total + 1 }

        it 'returns unprocessable entity error' do
          VCR.use_cassette('payment_sessions/failure') do
            post_request
          end

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['errors']).to eq(
            'adyen_id' => ["can't be blank"],
            'adyen_data' => ["can't be blank"],
            'expires_at' => ["can't be blank"],
            'amount' => ["can't be greater than allowed payment amount of #{order.total}"]
          )
        end

        context 'when there is already another order payment' do
          let(:amount) { order.total }

          before do
            create(:payment, state: 'completed', order: order, amount: order.total - 30)
            order.update_with_updater!
          end

          it 'returns unprocessable entity error' do
            VCR.use_cassette('payment_sessions/success_without_optional_params') do
              post_request
            end

            expect(response).to have_http_status(:unprocessable_content)
          end
        end
      end
    end

    context 'without headers' do
      let(:headers) { {} }

      it 'returns not found error' do
        post_request

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without adyen gateway' do
      let(:adyen_gateway) { nil }

      it 'returns error when adyen gateway is not present' do
        post_request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('Adyen gateway is not present')
      end
    end

    context 'with invalid order token' do
      let(:order_token) { 'invalid_token' }

      let(:params) do
        {
          payment_session: {
            amount: amount
          }
        }
      end

      it 'returns not found error' do
        post_request

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v2/storefront/adyen/payment_sessions/:id/complete' do
    subject(:post_request) { post url, params: params, headers: headers }

    let(:payment_session) { create(:payment_session, amount: order.total, order: order, user: user, adyen_id: payment_session_id, payment_method: adyen_gateway) }
    let(:payment_session_id) { 'CS4FBB6F827EC53AC7' }
    let(:session_result) { 'resultData' }

    let(:url) { "/api/v2/storefront/adyen/payment_sessions/#{payment_session.id}/complete" }
    let(:params) { { session_result: session_result } }

    before do
      order.update(email: 'test@example.com')
    end

    it 'completes the payment session ' do
      VCR.use_cassette('payment_session_results/success/completed') do
        post_request
      end

      expect(response).to have_http_status(:ok)
      expect(payment_session.reload.status).to eq('completed')
    end

    it 'completes the order' do
      VCR.use_cassette('payment_session_results/success/completed') do
        post_request
      end

      expect(response).to have_http_status(:ok)
      expect(order.reload.state).to eq('complete')
    end

    context 'when payment session was already completed' do
      before do
        VCR.use_cassette('payment_session_results/success/completed') do
          post url, params: params, headers: headers
        end
      end

      it 'keeps the payment session and order as completed' do
        VCR.use_cassette('payment_session_results/success/completed') do
          post_request
        end

        expect(response).to have_http_status(:not_found) # we look in user incomplete orders in this request
        expect(payment_session.reload.status).to eq('completed')
        expect(order.reload.state).to eq('complete')

        expect(order.payments.count).to eq(1)
        expect(order.payments.first.state).to eq('completed')
      end
    end

    context 'when payment session is pending' do
      it 'creates a payment with processing status' do
        VCR.use_cassette('payment_session_results/success/payment_pending') do
          post_request
        end

        expect(response).to have_http_status(:ok)
        expect(payment_session.reload.status).to eq('pending')
        expect(order.reload.state).to eq('payment')
        expect(order.payments.first.state).to eq('processing')
      end
    end

    context 'when payment session is canceled' do
      it 'voids the payment' do
        VCR.use_cassette('payment_session_results/success/canceled') do
          post_request
        end

        expect(response).to have_http_status(:ok)
        expect(payment_session.reload.status).to eq('canceled')
        expect(order.reload.state).to eq('payment')
        expect(order.payments.first.state).to eq('void')
      end
    end

    context 'when payment session is expired' do
      it 'fails the payment' do
        VCR.use_cassette('payment_session_results/success/expired') do
          post_request
        end

        expect(response).to have_http_status(:ok)
        expect(payment_session.reload.status).to eq('refused')
        expect(order.reload.state).to eq('payment')
        expect(order.payments.first.state).to eq('failed')
      end
    end

    context 'when payment session is refused' do
      it 'fails the payment' do
        VCR.use_cassette('payment_session_results/success/refused') do
          post_request
        end

        expect(response).to have_http_status(:ok)
        expect(payment_session.reload.status).to eq('refused')
        expect(order.reload.state).to eq('payment')
        expect(order.payments.first.state).to eq('failed')
      end
    end
  end

  describe 'GET /api/v2/storefront/adyen/payment_sessions/:id' do
    subject(:get_request) { get url, params: params, headers: headers }

    let(:payment_session) { create(:payment_session, amount: order.total, order: order, user: user, payment_method: adyen_gateway) }
    let(:url) { "/api/v2/storefront/adyen/payment_sessions/#{payment_session.id}" }
    let(:params) { {} }

    context 'with authenticated user' do
      context 'with valid payment session' do
        it 'returns payment session data' do
          get_request

          expect(response).to have_http_status(:ok)

          json_data = json_response['data']
          expect(json_data['type']).to eq('adyen_payment_session')
          expect(json_data['id']).to eq(payment_session.id.to_s)
          expect(json_data['attributes']['adyen_id']).to eq(payment_session.adyen_id)
          expect(json_data['attributes']['amount']).to eq(payment_session.amount.to_f.to_s)
          expect(json_data['attributes']['status']).to eq(payment_session.status)
          expect(json_data['attributes']['currency']).to eq(payment_session.currency)
          expect(json_data['attributes']['channel']).to eq(payment_session.channel)
          expect(json_data['attributes']['return_url']).to eq(payment_session.return_url)
        end

        it 'includes correct relationships' do
          get_request

          expect(response).to have_http_status(:ok)

          json_data = json_response['data']
          expect(json_data['relationships']['order']['data']['id']).to eq(order.id.to_s)
          expect(json_data['relationships']['user']['data']['id']).to eq(user.id.to_s)
          expect(json_data['relationships']['payment_method']['data']['id']).to eq(adyen_gateway.id.to_s)
        end
      end

      context 'with non-existent payment session' do
        let(:url) { '/api/v2/storefront/adyen/payment_sessions/999999' }

        it 'returns not found error' do
          get_request

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'with payment session from different order' do
        let(:other_order) { create(:order_with_line_items) }
        let(:other_payment_session) { create(:payment_session, order: other_order, user: user, payment_method: adyen_gateway) }
        let(:url) { "/api/v2/storefront/adyen/payment_sessions/#{other_payment_session.id}" }

        it 'returns not found error' do
          get_request

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'with invalid order token' do
      let(:order_token) { 'invalid_token' }

      it 'returns not found error' do
        get_request

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
