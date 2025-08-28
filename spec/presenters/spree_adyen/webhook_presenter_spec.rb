require 'spec_helper'

RSpec.describe SpreeAdyen::WebhookPayloadPresenter do
  subject(:presenter) { described_class.new(url) }

  let(:url) { 'https://example.com/webhook' }

  before do
    Timecop.freeze(Time.zone.local(2025, 1, 1, 13, 12, 0))
  end

  let(:expected_payload) do
    {
      url: url,
      description: "Webhook created by SpreeAdyen on 2025-01-01 13:12:00",
      active: true,
      communicationFormat: 'json',
      type: 'standard'
    }
  end

  describe '#to_h' do
    it 'returns the correct payload' do
      expect(presenter.to_h).to eq(expected_payload)
    end
  end
end