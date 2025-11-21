module SpreeAdyen
  module Webhooks
    class ProcessCaptureEventJob < SpreeAdyen::BaseJob
      def perform(payload)
        event = SpreeAdyen::Webhooks::Event.new(event_data: payload)
        SpreeAdyen::Webhooks::EventProcessors::CaptureEventProcessor.new(event).call
      end
    end
  end
end
