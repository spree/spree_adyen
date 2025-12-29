# this is the endpoint that Adyen JS SDK will redirect customer to after payment
# it will handle the payment session status and process the payment
module SpreeAdyen
  class PaymentSessionsController < Spree::BaseController
    include Spree::CheckoutAnalyticsHelper if defined?(Spree::CheckoutAnalyticsHelper)

    # GET /adyen/payment_sessions/redirect
    def redirect
      @payment_session = SpreeAdyen::PaymentSession.find_by(adyen_id: params[:sessionId])
      render layout: 'spree_adyen/default'
    end

    # GET /adyen/payment_sessions
    def show
      @payment_session = SpreeAdyen::PaymentSession.find_by!(adyen_id: params[:sessionId])
      @order = @payment_session.order
      # handle duplicated requests or already processed through webhook
      if @payment_session.canceled? || @order.canceled?
        redirect_to spree.cart_path, status: :see_other
        return
      elsif @order.completed?
        redirect_to spree.checkout_complete_path(@order.token), status: :see_other
        return
      end

      SpreeAdyen::PaymentSessions::ProcessWithResult.new(payment_session: @payment_session, session_result: params[:sessionResult]).call

      if @payment_session.completed?
        handle_success
      elsif @payment_session.pending?
        handle_pending_payment
      elsif @payment_session.canceled?
        redirect_to spree.checkout_path(@order.token), status: :see_other
      elsif @payment_session.refused?
        handle_failure
      end
    rescue Spree::Core::GatewayError => e
      handle_failure(e.message)
    end

    private

    # TODO: handle pending payment
    def handle_pending_payment; end

    def handle_success
      # update the payment session status

      # set the session flag to indicate that the order was placed now
      track_checkout_completed if @order.completed?

      redirect_to spree.checkout_complete_path(@order.token), status: :see_other
    end

    def handle_failure(message = nil)
      flash[:error] = message || Spree.t("adyen.payment_session_errors.#{@payment_session.status}")

      Rails.logger.error("Payment failed for order #{@order.id}: #{@payment_session.status}")

      # this should be a rare race condition, but we need to handle it
      @order.payments.valid.find_by(response_code: @payment_session.id)&.void!

      redirect_to spree.checkout_path(@order.token), status: :see_other
    end
  end
end
