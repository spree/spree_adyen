module SpreeAdyen
  # use this serializer to configure the Adyen Drop-in component
  # https://docs.adyen.com/online-payments/build-your-integration/sessions-flow/?platform=Web&integration=Drop-in&version=6.18.1&tab=embed_script_and_stylesheet_1_2#configure
  class CheckoutPresenter
    def initialize(payment_session)
      @payment_session = payment_session
    end

    def to_json(*_args)
      @to_json ||= to_h.to_json
    end

    def to_h
      @to_h ||= {
        session: {
          id: payment_session.adyen_id,
          sessionData: payment_session.adyen_data
        },
        environment: payment_session.payment_method.environment,

        amount: {
          value: Spree::Money.new(payment_session.amount, currency: currency).cents,
          currency: currency
        },
        countryCode: country_iso,
        locale: locale,
        clientKey: payment_session.payment_method.preferred_client_key,
        showPayButton: true
      }
    end

    private

    attr_reader :payment_session

    delegate :currency, :order, to: :payment_session
    delegate :store, :user, to: :order

    def locale
      order.try(:locale) || 'en-US'
    end

    def country_iso
      address&.country_iso || store.default_country_iso || 'US'
    end

    def address
      @address ||= order.bill_address || user&.bill_address || order.ship_address
    end
  end
end
