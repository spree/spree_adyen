require 'spec_helper'

RSpec.describe SpreeAdyen::CustomDomainDecorator do
  let(:store) { Spree::Store.default }

  describe '#after_commit :add_allowed_origin' do
    subject(:create_custom_domain) { create(:custom_domain, store: store) }

    context 'with an Adyen gateway' do
      before { create(:adyen_gateway, stores: [store]) }

      it 'enqueues a job' do
        expect { create_custom_domain }.to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob)
      end
    end

    context 'without an Adyen gateway' do
      before { create(:adyen_gateway, stores: [create(:store)]) }

      it 'does not enqueue a job' do
        expect { create_custom_domain }.not_to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob)
      end
    end
  end
end
