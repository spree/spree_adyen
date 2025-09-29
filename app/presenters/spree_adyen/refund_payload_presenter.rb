module SpreeAdyen
  class RefundPayloadPresenter
    REFERENCE_SUFFIX = 'refund'.freeze

    def initialize(amount_in_cents:, currency:, payment_method:, payment:, refund:)
      @amount_in_cents = amount_in_cents
      @currency = currency
      @payment_method = payment_method
      @payment = payment
      @refund = refund
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

    attr_reader :amount_in_cents, :currency, :payment_method, :payment, :refund

    def reference
      [
        payment.order.number,
        payment_method.id,
        payment.response_code,
        REFERENCE_SUFFIX,
        refund.id
      ].join('_')
    end
  end
end
