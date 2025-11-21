module SpreeAdyen
  module PaymentDecorator
    def self.prepended(base)
      base.state_machine.event :started_processing do
        transition from: [:checkout, :pending, :completed, :processing, :capture_pending, :void_pending], to: :processing
      end

      base.state_machine.event :pend_capture do
        transition from: [:pending, :processing, :checkout], to: :capture_pending
      end

      base.state_machine.event :pend_void do
        transition from: [:pending, :processing, :checkout], to: :void_pending
      end
    end

    def capture!(amount = nil)
      if payment_method.adyen? && !capture_pending?
        request_capture!(amount)
      else
        super(amount)
      end
    end

    def void_transaction!
      if payment_method.adyen? && !void_pending?
        request_void!
      else
        super
      end
    end

    # Takes the amount in cents to request a capture of the payment.
    # This is used instead of #capture! for Adyen that sends the capture result via a webhook.
    def request_capture!(amount = nil)
      return true if completed? || capture_pending?

      amount ||= money.amount_in_cents

      protect_from_connection_error do
        response = payment_method.request_capture(amount, response_code, gateway_options)
        handle_response(response, :pend_capture, :failure)
      end
    end

    # Sends a request to void the payment.
    # This is used instead of #void_transaction! for Adyen that sends the void result via a webhook.
    def request_void!
      return true if void? || void_pending?

      started_processing!
      protect_from_connection_error do
        response = payment_method.request_void(response_code, source, gateway_options)
        handle_response(response, :pend_void, :failure)
      end
    end
  end
end

Spree::Payment.prepend(SpreeAdyen::PaymentDecorator)
