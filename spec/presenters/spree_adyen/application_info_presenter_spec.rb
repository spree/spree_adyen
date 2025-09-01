require 'spec_helper'

RSpec.describe SpreeAdyen::ApplicationInfoPresenter do
  subject { described_class.new.to_h }

  let(:expected_hash) do
    {
      applicationInfo: {
        externalPlatform: {
          name: 'Spree Commerce',
          version: '42.0.0',
          integrator: 'Vendo Connect Inc.'
        },
        merchantApplication: {
          name: 'Community Edition',
          version: '0.0.1'
        }
      }
    }
  end

  before do
    allow(Spree).to receive(:version).and_return('42.0.0')
    allow(SpreeAdyen).to receive(:version).and_return('0.0.1')
  end

  it 'returns the correct hash' do
    expect(subject).to eq(expected_hash)
  end
end
