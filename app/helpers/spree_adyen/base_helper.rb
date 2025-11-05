module SpreeAdyen
  module BaseHelper
    def current_adyen_gateway
      @current_adyen_gateway ||= current_store.adyen_gateway
    end

    def current_adyen_payment_session
      return if current_adyen_gateway.nil?

      @current_adyen_payment_session ||= SpreeAdyen::PaymentSessions::FindOrCreate.new(
        order: @order,
        amount: @order.total_minus_store_credits,
        user: @order.user,
        payment_method: current_adyen_gateway
      ).call&.value
    end
  end
end
