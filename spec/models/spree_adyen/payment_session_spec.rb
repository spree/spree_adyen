require 'spec_helper'

RSpec.describe SpreeAdyen::PaymentSession do
  subject(:payment_session) { build(:payment_session, order: order, return_url: nil, channel: nil) }

  let(:order) { create(:order_with_line_items, store: store) }
  let(:store) { create(:store, url: 'www.example.com') }

  describe 'state machine' do
    describe 'initial state' do
      subject(:initial_state) { payment_session.status }

      it { is_expected.to eq('initial') }
    end

    describe 'pending! event' do
      subject(:pending_event) { payment_session.pending! }

      it 'updates status to pending' do
        expect { pending_event }.to change(payment_session, :status).to('pending')
      end
    end

    describe 'complete! event' do
      subject(:complete_event) { payment_session.complete! }

      it 'updates status to completed' do
        expect { complete_event }.to change(payment_session, :status).to('completed')
      end
    end

    describe 'cancel! event' do
      subject(:cancel_event) { payment_session.cancel! }

      it 'updates status to canceled' do
        expect { cancel_event }.to change(payment_session, :status).to('canceled')
      end
    end

    describe 'refuse! event' do
      subject(:refuse_event) { payment_session.refuse! }

      it 'updates status to refused' do
        expect { refuse_event }.to change(payment_session, :status).to('refused')
      end
    end
  end

  describe 'scopes' do
    subject(:payment_session) { create(:payment_session, order: order, return_url: nil, channel: nil) }

    describe 'not_expired' do
      subject(:not_expired_scope) { described_class.not_expired }

      before do
        Timecop.freeze(Time.current - 1.day) { create(:payment_session, expires_at: Time.current + 1.minute) }
        payment_session
      end

      it 'returns payment sessions with expires_at in the future' do
        expect(not_expired_scope).to eq([payment_session])
      end
    end
  end

  describe 'validations' do
    describe 'expiration_date_cannot_be_in_the_past_or_later_than_24_hours' do
      subject(:validation) { payment_session.valid? }

      context 'on update' do
        subject(:payment_session) { create(:payment_session, expires_at: Time.current + 1.minute) }

        context 'when expires_at is in the past' do
          before { Timecop.freeze(1.day.ago) { payment_session } }

          it { is_expected.to be_valid }
        end

        context 'when expires_at is in the future' do
          it { is_expected.to be_valid }
        end
      end

      context 'on create' do
        subject(:payment_session) { build(:payment_session, expires_at: expires_at, order: order) }

        context 'when expires_at is in the past' do
          let(:expires_at) { 1.day.ago }

          it { is_expected.to be_invalid }
        end

        context 'when expires_at is in the future' do
          let(:expires_at) { 1.day.from_now }

          it { is_expected.to be_valid }
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'set_default_channel' do
      it 'sets the default channel' do
        expect { payment_session.validate }.to change(payment_session, :channel).to('Web')
      end
    end

    describe 'set_return_url' do
      before do
        allow(store).to receive(:url_or_custom_domain).and_return('url-or-custom-domain.com')
      end

      it 'sets the redirect url' do
        expect { payment_session.validate }.to change(payment_session, :return_url).to('http://url-or-custom-domain.com/adyen/payment_sessions/redirect')
      end
    end
  end
end
