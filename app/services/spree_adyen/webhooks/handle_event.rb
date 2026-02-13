module SpreeAdyen
  module Webhooks
    class HandleEvent
      def initialize(event_payload:)
        @event_payload = event_payload
      end

      def call
        # event not supported - skip
        if event_class.nil?
          Rails.logger.info("[SpreeAdyen][#{event_code}]: Skipping not supported event")
          return
        end

        Rails.logger.info("[SpreeAdyen][#{event_id}]: Event received")
        return unless event.code.in?(SpreeAdyen.event_handlers.keys)

        Rails.logger.info("[SpreeAdyen][#{event_id}]: Event queued")
        SpreeAdyen.event_handlers[event.code]
          .set(wait: SpreeAdyen::Config.webhook_delay_in_seconds.seconds)
          .perform_later(event.payload)
      end

      def event
        @event ||= event_class.new(event_data: event_payload)
      end

      private

      attr_reader :event_payload

      delegate :id, to: :event, prefix: true

      def event_class
        @event_class ||= SpreeAdyen.events[event_code]
      end

      def event_code
        @event_code ||= event_payload.dig('notificationItems', 0, 'NotificationRequestItem', 'eventCode') || event_payload['type']
      end
    end
  end
end
