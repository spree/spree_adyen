# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpreeAdyen::WebhooksController, type: :controller do
  include ActiveJob::TestHelper
  render_views

  let(:payment_method) { create(:adyen_gateway, preferred_hmac_key: 'hmac_key') }
  let(:order) { create(:order_with_line_items, number: '1234567890', state: 'payment') }
  let(:valid_hmac) { true }
  let(:valid_previous_hmac) { false }

  before do
    allow_any_instance_of(Adyen::Utils::HmacValidator).to receive(:valid_webhook_hmac?).and_return(valid_hmac)
    allow_any_instance_of(Adyen::Utils::HmacValidator).to receive(:valid_webhook_hmac?).with(kind_of(String), 'hmac_key').and_return(valid_hmac)
    allow_any_instance_of(Adyen::Utils::HmacValidator).to receive(:valid_webhook_hmac?).with(kind_of(String), 'previous_hmac_key').and_return(valid_previous_hmac)
    allow_any_instance_of(SpreeAdyen::Webhooks::Event).to receive(:payment_method_id).and_return(payment_method.id)
    allow_any_instance_of(SpreeAdyen::Webhooks::Event).to receive(:amount).and_return(Spree::Money.new(order.total_minus_store_credits, currency: order.currency))
  end

  describe 'POST #create' do
    subject { post :create, params: params, as: :json }
    
    describe 'hmac validation' do
      let(:params) { JSON.parse(file_fixture('webhooks/authorised/success.json').read) }

      context 'with valid hmac' do
        let(:valid_hmac) { true }

        it 'returns ok' do
          subject

          expect(response).to have_http_status(:ok)
        end
      end

      context 'with invalid hmac' do
        let(:valid_hmac) { false }

        it 'returns unauthorized' do
          subject

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'with valid previous hmac' do
        let(:valid_previous_hmac) { true }
        let(:valid_hmac) { false }

        it 'returns ok' do
          subject
        end
      end
    end

    describe 'full webhook flow' do
      describe 'authorisation event' do
        let(:payment) { create(:payment, state: 'processing', skip_source_requirement: true, payment_method: payment_method, source: nil, order: order, amount: order.total_minus_store_credits, response_code: 'webhooks_authorisation_success_checkout_session_id') }
        let!(:payment_session) { create(:payment_session, amount: order.total_minus_store_credits, currency: order.currency, payment_method: payment_method, order: order, adyen_id: 'webhooks_authorisation_success_checkout_session_id') }

        before do
          payment
        end

        context 'with valid payment' do
          context 'with other payment (blik)' do
            let(:params) { JSON.parse(file_fixture('webhooks/authorised/success.json').read) }

            it 'creates a job' do
              expect { subject }.to have_enqueued_job(SpreeAdyen::Webhooks::ProcessAuthorisationEventJob)

              expect(response).to have_http_status(:ok)
            end

            it 'completes the order' do
              perform_enqueued_jobs do
                expect { subject }.to change { order.reload.completed? }.from(false).to(true)
              end

              expect(response).to have_http_status(:ok)
            end

            it 'completes the payment' do
              perform_enqueued_jobs do
                expect { subject }.to change { payment.reload.state }.from('processing').to('completed')
              end

              expect(response).to have_http_status(:ok)
            end

            it 'creates a blik payment source' do
              perform_enqueued_jobs do
                subject
              end

              expect(payment.reload.source).to be_a(SpreeAdyen::PaymentSources::Blik)
              expect(response).to have_http_status(:ok)
            end

            context 'without payment' do
              let(:payment) { nil }

              it 'creates a payment' do
                perform_enqueued_jobs do
                  expect { subject }.to change { order.payments.count }.by(1)
                end
              end
            end

            context 'without payment session' do
              let(:payment) { nil }
              let(:payment_session) { nil }
              let(:params) { JSON.parse(file_fixture('webhooks/authorised/success_no_session.json').read) }

              it 'creates a payment' do
                perform_enqueued_jobs do
                  expect { subject }.to change { order.payments.count }.by(1)
                end
              end

              it 'completes the order' do
                perform_enqueued_jobs do
                  expect { subject }.to change { order.reload.completed? }.from(false).to(true)
                end
              end
            end
          end

          context 'with card details' do
            let(:params) { JSON.parse(file_fixture('webhooks/authorised/success_with_cc_details.json').read) }

            it 'creates a job' do
              expect { subject }.to have_enqueued_job(SpreeAdyen::Webhooks::ProcessAuthorisationEventJob)

              expect(response).to have_http_status(:ok)
            end

            it 'completes the order' do
              perform_enqueued_jobs do
                expect { subject }.to change { order.reload.completed? }.from(false).to(true)
              end

              expect(response).to have_http_status(:ok)
            end

            it 'completes the payment' do
              perform_enqueued_jobs do
                expect { subject }.to change { payment.reload.state }.from('processing').to('completed')
              end

              expect(response).to have_http_status(:ok)
            end

            it 'creates a credit card with card details' do
              perform_enqueued_jobs do
                subject
              end

              cc = payment.reload.source
              expect(cc).to be_a(Spree::CreditCard)
              expect(cc.gateway_payment_profile_id).to eq('webhooks_authorisation_success_stored_payment_method_id')
              expect(cc.last_digits).to eq('7777')
              expect(cc.year).to eq(2077)
              expect(cc.month).to eq(12)
              expect(cc.cc_type).to eq('master')

              expect(response).to have_http_status(:ok)
            end

            context 'without payment' do
              let(:payment) { nil }

              it 'creates a payment' do
                perform_enqueued_jobs do
                  expect { subject }.to change { order.payments.count }.by(1)
                end
              end
            end
          end
        end

        context 'with failed payment' do
          let(:params) { JSON.parse(file_fixture('webhooks/authorised/failure.json').read) }

          context 'with not completed order' do
            it 'does not complete the order' do
              perform_enqueued_jobs do
                expect { subject }.not_to change { order.reload.completed? }
              end

              expect(response).to have_http_status(:ok)
            end
          end

          context 'with completed order' do
            let(:order) { create(:order_with_line_items, number: '1234567890', state: 'complete', completed_at: Time.current) }
            let!(:payment) { create(:payment, state: 'processing', skip_source_requirement: true, payment_method: payment_method, source: nil, order: order, amount: order.total_minus_store_credits, response_code: 'webhooks_authorisation_success_checkout_session_id') }

            it 'reports an error' do
              perform_enqueued_jobs do
                expect(Rails.error).to receive(:unexpected).with('Payment failed for previously completed order', context: { order_id: order.id, event: anything }, source: 'spree_adyen')

                subject
              end

              expect(response).to have_http_status(:ok)
            end
          end

          context 'without payment' do
            let(:payment) { nil }

            it 'creates a payment' do
              perform_enqueued_jobs do
                expect { subject }.to change { order.payments.count }.by(1)
              end
            end
          end
        end
      end
    end
  end
end
