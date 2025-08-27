module SpreeAdyen
  module StoreDecorator
    def adyen_gateway
      @adyen_gateway ||= payment_methods.adyen.active.last
    end

    def handle_code_changes
      super

      return if adyen_gateway.blank?

      SpreeAdyen::AddAllowedOriginJob.perform_later(id, adyen_gateway.id)
    end
  end
end

Spree::Store.prepend(SpreeAdyen::StoreDecorator)
