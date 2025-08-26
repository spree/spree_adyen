module SpreeAdyen
  class RefundPayloadPresenter
    REFERENCE_SUFFIX = 'refund'.freeze

    def initialize(amount_in_cents:, currency:, payment_method:, payment:)
      @amount_in_cents = amount_in_cents
      @currency = currency
      @payment_method = payment_method
      @payment = payment
    end

    def to_h
      {
        amount: {
          value: amount_in_cents,
          currency: currency
        },
        reference: reference,
        merchantAccount: payment_method.preferred_merchant_account
      }.merge!(SpreeAdyen::ApplicationInfoPresenter.new.to_h)
    end

    private

    attr_reader :amount_in_cents, :currency, :payment_method, :payment

    def reference
      [
        payment.order.number,
        payment_method.id,
        payment.response_code,
        REFERENCE_SUFFIX
      ].join('_')
    end
  end
end
