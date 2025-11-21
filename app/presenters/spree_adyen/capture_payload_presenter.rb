module SpreeAdyen
  class CapturePayloadPresenter
    REFERENCE_SUFFIX = 'capture'.freeze

    def initialize(amount_in_cents:, payment:, payment_method:)
      @amount_in_cents = amount_in_cents
      @payment = payment
      @order = payment.order
      @payment_method = payment_method
    end

    def to_h
      {
        amount: {
          value: amount_in_cents,
          currency: payment.currency
        },
        reference: reference,
        merchantAccount: payment_method.preferred_merchant_account
      }.merge!(SpreeAdyen::ApplicationInfoPresenter.new.to_h)
    end

    private

    attr_reader :amount_in_cents, :payment, :order, :payment_method

    def reference
      [
        order.number,
        payment_method.id,
        payment.response_code,
        REFERENCE_SUFFIX
      ].join('_')
    end
  end
end
