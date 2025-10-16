require 'spec_helper'

RSpec.describe 'Apple Pay domain verification requests' do
  describe 'GET /.well-known/apple-developer-merchantid-domain-association' do
    subject { get '/.well-known/apple-developer-merchantid-domain-association' }

    let(:store) { Spree::Store.default }

    before { host!(store.url) }

    context 'with the apple domain association file attached' do
      let!(:adyen_gateway) { create(:adyen_gateway, :with_apple_domain_association_file, stores: [store], active: active) }

      context 'when the Adyen gateway is active' do
        let(:active) { true }

        it 'responds with the attached apple domain association file content' do
          subject

          expect(response).to be_ok
          expect(response.body).to eq('ABCDEF123456')
        end
      end

      context 'when the Adyen gateway is inactive' do
        let(:active) { false }

        it 'raises a not found error' do
          subject
          expect(response).to be_not_found
        end
      end
    end

    context 'without the apple domain association file attached' do
      let!(:adyen_gateway) { create(:adyen_gateway, stores: [store], active: true) }

      it 'raises a not found error' do
        subject
        expect(response).to be_not_found
      end
    end

    context 'for a store without the Adyen gateway' do
      let!(:adyen_gateway) { create(:adyen_gateway, stores: [create(:store)]) }

      it 'raises a not found error' do
        subject
        expect(response).to be_not_found
      end
    end
  end
end
