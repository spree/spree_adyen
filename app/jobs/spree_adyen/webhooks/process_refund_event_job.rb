module SpreeAdyen
  module Webhooks
    class ProcessRefundEventJob < SpreeAdyen::BaseJob
      def perform(payload)
        event = SpreeAdyen::Webhooks::Event.new(event_data: payload)
        SpreeAdyen::Webhooks::EventProcessors::RefundEventProcessor.new(event).call
      end
    end
  end
end
