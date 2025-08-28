require 'spec_helper'

RSpec.describe SpreeAdyen::AddAllowedOriginJob do
  subject { described_class.new.perform(record.id, gateway.id, model_type) }

  let(:gateway) { create(:adyen_gateway) }
  
  let(:add_allowed_origin_instance) { double(call: true) }

  before do
    allow(SpreeAdyen::Gateways::AddAllowedOrigin).to receive(:new).with(record, gateway).and_return(add_allowed_origin_instance)
    allow(add_allowed_origin_instance).to receive(:call).and_return(true)
  end

  context 'when the model type is store' do
    let(:model_type) { 'store' }
    let(:record) { create(:store) }

    it 'calls SpreeAdyen::Gateways::AddAllowedOrigin with the correct arguments' do
      expect(add_allowed_origin_instance).to receive(:call)

      subject
    end
  end

  context 'when the model type is custom_domain' do
    let(:model_type) { 'custom_domain' }
    let(:record) { create(:custom_domain) }

    it 'calls SpreeAdyen::Gateways::AddAllowedOrigin with the correct arguments' do
      expect(add_allowed_origin_instance).to receive(:call)

      subject
    end

    context 'when the model type symbol' do
      let(:model_type) { :custom_domain }
      let(:record) { create(:custom_domain) }

      it 'normalizes model_type and calls SpreeAdyen::Gateways::AddAllowedOrigin with the correct arguments' do
        expect(add_allowed_origin_instance).to receive(:call)

        subject
      end
    end

    context 'when the model type is not a valid type' do
      let(:model_type) { 'invalid' }
      let(:record) { create(:store) }

      it 'raises an error' do
        expect { subject }.to raise_error(ActiveSupport::ErrorReporter::UnexpectedError, "RuntimeError: Unexpected klass_type: invalid")
      end
    end
  end
end
