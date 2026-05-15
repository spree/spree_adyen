module SpreeAdyen
  module PaymentSetupSessions
    # Processes an AUTHORISATION webhook for a zero-auth (tokenization-only) setup session.
    # Creates the payment source from the stored payment method ID and transitions the
    # session. Idempotent — safe to invoke for retries.
    class HandleAuthorisation
      def initialize(setup_session:, event:)
        @setup_session = setup_session
        @event = event
        @gateway = setup_session.payment_method
        @user = setup_session.customer
      end

      def call
        return setup_session if setup_session.completed?

        Rails.logger.info("[SpreeAdyen][setup_session=#{setup_session.id}][#{event.psp_reference}]: Processing setup authorisation")

        if event.success?
          handle_success
        else
          handle_failure
        end

        setup_session
      end

      private

      attr_reader :setup_session, :event, :gateway, :user

      def handle_success
        source = SpreeAdyen::Webhooks::Actions::CreateSource.new(
          event: event,
          payment_method: gateway,
          user: user
        ).call

        setup_session.update!(payment_source: source) if source.present?
        setup_session.complete if setup_session.can_complete?
      end

      def handle_failure
        setup_session.fail if setup_session.can_fail?
      end
    end
  end
end
