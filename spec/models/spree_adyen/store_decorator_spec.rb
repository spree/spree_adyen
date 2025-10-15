require 'spec_helper'

RSpec.describe SpreeAdyen::StoreDecorator do
  subject(:store) { create(:store) }

  describe '#after_commit :handle_code_changes' do
    subject { store.update!(code: new_code) }

    describe 'adding allowed origin to Adyen' do
      let(:store) { create(:store, code: 'store-with-adyen-1') }

      before { create(:adyen_gateway, stores: [store]) }

      context 'when code changed' do
        let(:new_code) { 'store-with-stripe-2' }

        it 'enqueues a job for registering a domain in Stripe' do
          expect { subject }.to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob)
        end
      end

      context "when code didn't change" do
        let(:new_code) { store.code }

        it 'does not enqueue a job' do
          expect { subject }.not_to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob)
        end
      end
    end
  end
end