module SpreeAdyen
  module OrderDecorator
    def self.prepended(base)
      base.has_many :adyen_payment_sessions, class_name: 'SpreeAdyen::PaymentSession', dependent: :destroy
    end

    def outdate_payment_sessions
      adyen_payment_sessions
        .where.not(currency: currency).or(adyen_payment_sessions.where.not(amount: total_minus_store_credits))
        .with_status(:initial)
        .each(&:destroy)
    end

    def can_create_adyen_payment_session?
      state.in?(%w[confirm payment])
    end
  end
end

Spree::Order.prepend(SpreeAdyen::OrderDecorator)
Spree::Order.register_update_hook :outdate_payment_sessions
