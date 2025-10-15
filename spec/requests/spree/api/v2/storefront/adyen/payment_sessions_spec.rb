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

            expect(response).to have_http_status(:unprocessable_entity)
            expect(json_response['errors']).to be_present
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

            expect(response).to have_http_status(:unprocessable_entity)
            expect(json_response['errors']).to be_present
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

        expect(response).to have_http_status(:unprocessable_entity)
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
