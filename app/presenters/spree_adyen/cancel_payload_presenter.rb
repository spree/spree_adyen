module SpreeAdyen
  class CancelPayloadPresenter
    REFERENCE_SUFFIX = 'cancel'.freeze

    def initialize(payment:, payment_method:)
      @payment = payment
      @order = payment.order
      @payment_method = payment_method
    end

    def to_h
      {
        reference: reference,
        merchantAccount: payment_method.preferred_merchant_account
      }.merge!(SpreeAdyen::ApplicationInfoPresenter.new.to_h)
    end

    private

    attr_reader :payment, :order, :payment_method

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
