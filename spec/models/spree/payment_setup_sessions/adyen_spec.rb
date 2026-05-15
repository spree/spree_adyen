require 'spec_helper'

RSpec.describe Spree::PaymentSetupSessions::Adyen, type: :model do
  let(:store) { Spree::Store.default }
  let(:gateway) { create(:adyen_gateway, stores: [store]) }
  let(:user) { create(:user) }
  let(:setup_session) do
    described_class.create!(
      customer: user,
      payment_method: gateway,
      status: 'pending',
      external_id: 'CS_setup_abc',
      external_data: { 'session_data' => 'data-blob', 'channel' => 'Web', 'return_url' => 'https://example.com/return' }
    )
  end

  describe 'accessors' do
    it 'exposes adyen_id from external_id' do
      expect(setup_session.adyen_id).to eq('CS_setup_abc')
    end

    it 'exposes session_data from external_data' do
      expect(setup_session.session_data).to eq('data-blob')
    end

    it 'exposes channel with Web default' do
      expect(setup_session.channel).to eq('Web')

      no_channel = described_class.new(payment_method: gateway, external_data: {})
      expect(no_channel.channel).to eq('Web')
    end

    it 'exposes return_url from external_data' do
      expect(setup_session.return_url).to eq('https://example.com/return')
    end

    it 'delegates client_key to the payment method' do
      gateway.update!(preferred_client_key: 'client_xyz')
      expect(setup_session.client_key).to eq('client_xyz')
    end
  end

  describe '#successful?' do
    it 'is true only when status is completed' do
      expect(setup_session.successful?).to be(false)
      setup_session.update!(status: 'completed')
      expect(setup_session.successful?).to be(true)
    end
  end
end
