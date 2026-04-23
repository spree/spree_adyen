require 'spec_helper'

RSpec.describe SpreeAdyen::Gateways::Configure do
  subject(:service) { described_class.new(gateway).call }

  let(:gateway) { create(:adyen_gateway, stores: [store], preferred_hmac_key: hmac_key, preferred_webhook_id: webhook_id, preferred_merchant_account: nil) }
  let(:store) { create(:store, url: 'c33e96aee20a.ngrok-free.app') }

  before do
    Timecop.travel(1.day.ago) { gateway }
    create(:custom_domain, store: store, url: 'foo.store.example.com')
    create(:custom_domain, store: store, url: 'bar.store.example.com')
  end

  context 'when the webhook is not valid (invalid hmac or webhook id)' do
    let(:hmac_key) { 'DUADUAUDUADUAUDAU' }
    let(:webhook_id) { 'DUADUAUDUADUAUDAUBLEBLEBLEBLE' }

    it 'updates the webhook_id and hmac_key and merchant_account' do
      VCR.use_cassette('gateways/configure/success/webhook_not_valid') do
        expect { service }.to change(gateway, :preferred_webhook_id)
                         .and change(gateway, :preferred_hmac_key)
                         .and change(gateway, :previous_hmac_key).from(nil).to(hmac_key)
                         .and change(gateway, :preferred_merchant_account).to('SpreeCommerceECOM')
                         .and change(gateway, :updated_at)
      end
    end
  end

  context 'when the webhook is not set up' do
    let(:webhook_id) { nil }
    let(:hmac_key) { nil }

    it 'updates the webhook_id and hmac_key' do
      VCR.use_cassette('gateways/configure/success/webhook_not_set_up') do
        expect { service }.to change(gateway, :preferred_webhook_id)
                          .and change(gateway, :preferred_hmac_key)
                          .and change(gateway, :preferred_merchant_account).to('SpreeCommerceECOM')
                          .and change(gateway, :updated_at)
      end
    end

    it 'registers the webhook using the v3 webhook url' do
      VCR.use_cassette('gateways/configure/success/webhook_not_set_up') do
        expect(gateway).to receive(:set_up_webhook).with(gateway.webhook_url).and_call_original
        service
      end
    end

    context 'with legacy webhook handlers enabled' do
      before do
        allow(SpreeAdyen::Config).to receive(:[]).and_call_original
        allow(SpreeAdyen::Config).to receive(:[]).with(:use_legacy_webhook_handlers).and_return(true)
      end

      it 'registers the webhook using the legacy webhook url' do
        VCR.use_cassette('gateways/configure/success/webhook_not_set_up') do
          expect(gateway).to receive(:set_up_webhook).with("#{store.formatted_url}/adyen/webhooks").and_call_original
          service
        end
      end
    end
  end

  context 'when webhook is set up' do
    let(:hmac_key) { '803CB6B178ECEBD56C378B546AC75FEB786FA39352A51B370711377BCE763F63' }
    let(:webhook_id) { 'WBHK42CLX22322945MWKG7R6LH0000' }

    it 'does not update the webhook_id and hmac_key' do
      VCR.use_cassette('gateways/configure/success/webhook_set_up') do
        expect { service }.not_to change(gateway, :preferred_webhook_id)
      end
    end

    it 'updates other attributes' do
      VCR.use_cassette('gateways/configure/success/webhook_set_up') do
        expect { service }.to change(gateway, :preferred_merchant_account).to('SpreeCommerceECOM')
                          .and change(gateway, :updated_at)
      end
    end

    it 'enqueues AddAllowedOriginJob for the store' do
      VCR.use_cassette('gateways/configure/success/webhook_set_up') do
        expect { service }.to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob).with(store.id, gateway.id)
      end
    end

    it 'enqueues AddAllowedOriginJob for each custom domain' do
      VCR.use_cassette('gateways/configure/success/webhook_set_up') do
        custom_domains = store.custom_domains

        expect { service }.to have_enqueued_job(SpreeAdyen::AddAllowedOriginJob).with(custom_domains.first.id, gateway.id, 'custom_domain')
                          .and have_enqueued_job(SpreeAdyen::AddAllowedOriginJob).with(custom_domains.last.id, gateway.id, 'custom_domain')
      end
    end
  end
end
