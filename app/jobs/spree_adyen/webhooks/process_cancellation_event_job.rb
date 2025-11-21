module SpreeAdyen
  module Webhooks
    class ProcessCancellationEventJob < SpreeAdyen::BaseJob
      def perform(payload)
        event = SpreeAdyen::Webhooks::Event.new(event_data: payload)
        SpreeAdyen::Webhooks::EventProcessors::CancellationEventProcessor.new(event).call
      end
    end
  end
end
