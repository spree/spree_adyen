module SpreeAdyen
  module Webhooks
    class HandleEvent
      EVENT_HANDLERS = {
        'AUTHORISATION' => SpreeAdyen::Webhooks::ProcessAuthorisationEventJob,
        'CAPTURE' => SpreeAdyen::Webhooks::ProcessCaptureEventJob,
        'CANCELLATION' => SpreeAdyen::Webhooks::ProcessCancellationEventJob
      }.freeze

      def initialize(event_payload:)
        @event_payload = event_payload
      end

      def call
        Rails.logger.info("[SpreeAdyen][#{event_id}]: Event received")
        # event not supported - skip
        return unless event.code.in?(EVENT_HANDLERS.keys)

        Rails.logger.info("[SpreeAdyen][#{event_id}]: Event queued")
        EVENT_HANDLERS[event.code].set(wait: SpreeAdyen::Config.webhook_delay_in_seconds.seconds)
                                  .perform_later(event.payload)
      end

      def event
        @event ||= SpreeAdyen::Webhooks::Event.new(event_data: event_payload)
      end

      private

      attr_reader :event_payload

      delegate :id, to: :event, prefix: true
    end
  end
end
