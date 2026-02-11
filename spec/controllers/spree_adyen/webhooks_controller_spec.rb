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

    context 'for an unsupported event' do
      let(:params) do
        {
          'notificationItems' => [
            {
              'NotificationRequestItem' => {
                'eventCode' => 'UNSUPPORTED_EVENT_TYPE',
                'pspReference' => 'unsupported_psp_reference',
                'merchantAccountCode' => 'TestMerchant',
                'merchantReference' => order.number
              }
            }
          ]
        }
      end

      it 'returns ok' do
        subject

        expect(response).to have_http_status(:ok)
      end

      it 'logs the unsupported event' do
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with('[SpreeAdyen][UNSUPPORTED_EVENT_TYPE]: Event not supported')

        subject
      end

      it 'does not enqueue any job' do
        expect { subject }.not_to have_enqueued_job
      end
    end

    describe 'full webhook flow' do
      describe 'authorisation event' do
        let(:payment) { create(:payment, state: 'processing', skip_source_requirement: true, payment_method: payment_method, source: nil, order: order, amount: order.total_minus_store_credits, response_code: response_code) }
        let(:response_code) { 'webhooks_authorisation_success_checkout_session_id' }

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

            context 'when payment is not automatically captured' do
              before do
                payment_method.update(auto_capture: false)
              end

              it 'makes the payment pending' do
                perform_enqueued_jobs do
                  expect { subject }.to change { payment.reload.state }.from('processing').to('pending')
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

            context 'when payment is not automatically captured' do
              before do
                payment_method.update(auto_capture: false)
              end

              it 'makes the payment pending' do
                perform_enqueued_jobs do
                  expect { subject }.to change { payment.reload.state }.from('processing').to('pending')
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

          context 'when the payment response code is the PSP reference' do
            let(:response_code) { 'webhooks_psp_reference' }
            let(:params) { JSON.parse(file_fixture('webhooks/authorised/success_with_cc_details.json').read) }

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

            context 'when payment is not automatically captured' do
              before do
                payment_method.update(auto_capture: false)
              end

              it 'makes the payment pending' do
                perform_enqueued_jobs do
                  expect { subject }.to change { payment.reload.state }.from('processing').to('pending')
                end

                expect(response).to have_http_status(:ok)
              end

              context 'when payment is already pending' do
                before do
                  payment.source = create(:payment_source, payment_method: payment_method)
                  payment.save!
                  payment.pend!
                end

                it 'processes the webhook without errors' do
                  perform_enqueued_jobs do
                    expect { subject }.not_to change { payment.reload.state }
                  end

                  expect(response).to have_http_status(:ok)
                end
              end
            end

            context 'when payment is completed' do
              before do
                payment.source = create(:payment_source, payment_method: payment_method)
                payment.save!
                payment.complete!
              end

              it 'processes the webhook without errors' do
                perform_enqueued_jobs { subject }
                expect(response).to have_http_status(:ok)
              end
            end

            context 'when there is no session id' do
              let(:params) { JSON.parse(file_fixture('webhooks/authorised/success_no_session.json').read) }

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

      describe 'capture event' do
        let(:params) { JSON.parse(file_fixture('webhooks/capture/success.json').read) }

        let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: payment_method, amount: 100.0, response_code: response_code) }
        let(:payment_state) { 'capture_pending' }
        let(:response_code) { 'ABC123' }

        it 'schedules a job' do
          expect { subject }.to have_enqueued_job(SpreeAdyen::Webhooks::ProcessCaptureEventJob)
          expect(response).to have_http_status(:ok)
        end

        it 'captures the payment' do
          perform_enqueued_jobs do
            expect { subject }.to change { payment.reload.state }.from('capture_pending').to('completed')
          end

          expect(response).to have_http_status(:ok)
          expect(payment.reload.get_metafield(SpreeAdyen::Gateway::CAPTURE_PSP_REFERENCE_METAFIELD_KEY).value).to eq('capture_psp_reference')
        end

        context 'when payment is already captured' do
          let(:payment_state) { 'completed' }

          it 'keeps the payment completed' do
            perform_enqueued_jobs do
              expect { subject }.to_not change { payment.reload.state }
            end

            expect(response).to have_http_status(:ok)

            expect(payment.reload.state).to eq('completed')
            expect(payment.get_metafield(SpreeAdyen::Gateway::CAPTURE_PSP_REFERENCE_METAFIELD_KEY).value).to eq('capture_psp_reference')
          end
        end

        context 'when capturing failed' do
          let(:params) { JSON.parse(file_fixture('webhooks/capture/failure.json').read) }

          before do
            allow(Rails.error).to receive(:report)
          end

          it 'fails the payment' do
            perform_enqueued_jobs do
              expect { subject }.to change { payment.reload.state }.from('capture_pending').to('failed')
            end

            expect(response).to have_http_status(:ok)
            expect(payment.reload.gateway_processing_error_messages).to eq(['Capture failed: Insufficient balance on payment'])
          end

          it 'reports an error' do
            perform_enqueued_jobs { subject }

            expect(Rails.error).to have_received(:report).with(
              SpreeAdyen::CaptureError.new('Insufficient balance on payment'),
              context: { order_id: order.id, event: anything },
              source: 'spree_adyen'
            )
          end
        end
      end

      describe 'cancellation event' do
        let!(:payment) { create(:payment, state: payment_state, order: order, payment_method: payment_method, amount: 100.0, response_code: response_code) }
        let(:payment_state) { 'void_pending' }
        let(:response_code) { 'ABC123' }

        let(:params) { JSON.parse(file_fixture('webhooks/cancellation/success.json').read) }

        it 'creates a job' do
          expect { subject }.to have_enqueued_job(SpreeAdyen::Webhooks::ProcessCancellationEventJob)
        end

        it 'voids the payment' do
          perform_enqueued_jobs do
            expect { subject }.to change { payment.reload.state }.from('void_pending').to('void')
          end

          expect(response).to have_http_status(:ok)
          expect(payment.reload.get_metafield(SpreeAdyen::Gateway::CANCELLATION_PSP_REFERENCE_METAFIELD_KEY).value).to eq('cancellation_psp_reference')
        end

        context 'when payment is already voided' do
          let(:payment_state) { 'void' }

          it 'does nothing' do
            perform_enqueued_jobs do
              expect { subject }.to_not change { payment.reload.state }
            end

            expect(response).to have_http_status(:ok)

            expect(payment.reload.state).to eq('void')
            expect(payment.get_metafield(SpreeAdyen::Gateway::CANCELLATION_PSP_REFERENCE_METAFIELD_KEY).value).to eq('cancellation_psp_reference')
          end
        end

        context 'when voiding failed' do
          let(:params) { JSON.parse(file_fixture('webhooks/cancellation/failure.json').read) }

          before do
            allow(Rails.error).to receive(:report)
          end

          it 'makes the payment pending' do
            perform_enqueued_jobs do
              expect { subject }.to change { payment.reload.state }.from('void_pending').to('pending')
            end

            expect(response).to have_http_status(:ok)
            expect(payment.reload.gateway_processing_error_messages).to eq(['Cancellation failed: Transaction not found'])
          end

          it 'reports an error' do
            perform_enqueued_jobs { subject }

            expect(Rails.error).to have_received(:report).with(
              SpreeAdyen::CancellationError.new('Transaction not found'),
              context: { order_id: order.id, event: anything },
              source: 'spree_adyen'
            )
          end
        end
      end
    end
  end
end
