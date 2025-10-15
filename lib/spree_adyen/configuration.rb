module SpreeAdyen
  class Configuration < Spree::Preferences::Configuration
    # Some example preferences are shown below, for more information visit:
    # https://docs.spreecommerce.org/developer/contributing/creating-an-extension

    # preference :enabled, :boolean, default: true
    # preference :dark_chocolate, :boolean, default: true
    # preference :color, :string, default: 'Red'
    # preference :favorite_number, :integer
    # preference :supported_locales, :array, default: [:en]

    preference :payment_session_expiration_in_minutes, :integer, default: 60
    preference :webhook_delay_in_seconds, :integer, default: 5
  end
end
