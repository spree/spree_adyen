module SpreeAdyen
  module PaymentMethodDecorator
    ADYEN_TYPE = 'SpreeAdyen::Gateway'.freeze unless const_defined?(:ADYEN_TYPE)

    def self.prepended(base)
      base.scope :adyen, -> { where(type: ADYEN_TYPE) }
    end

    def adyen?
      type == ADYEN_TYPE
    end
  end
end

Spree::PaymentMethod.prepend(SpreeAdyen::PaymentMethodDecorator)
