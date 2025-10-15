module SpreeAdyen
  class PaymentSession < Base
    AVAILABLE_CHANNELS = {
      ios: 'iOS',
      android: 'Android',
      web: 'Web'
    }.freeze

    acts_as_paranoid
    #
    # Associations
    #
    belongs_to :order, class_name: 'Spree::Order'
    belongs_to :payment_method, class_name: 'Spree::PaymentMethod'
    belongs_to :user, class_name: Spree.user_class.name, optional: true

    #
    # Attributes
    #
    attribute :skip_expiration_date_validation, :boolean, default: false

    #
    # Validations
    #
    validates :order, :payment_method, presence: true
    validates :adyen_id, uniqueness: true, presence: true
    validates :adyen_data, :status, :expires_at, presence: true
    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :currency, presence: true
    validates :channel, presence: true, inclusion: { in: AVAILABLE_CHANNELS.values }
    validates :return_url, presence: true

    validate :amount_cannot_be_greater_than_order_total
    validate :currency_matches_order_currency
    validate :expiration_date_cannot_be_in_the_past_or_later_than_24_hours, on: :create, unless: :skip_expiration_date_validation

    scope :not_expired, -> { where('expires_at > ?', DateTime.current) }

    state_machine :status, initial: :initial do
      event :pending do
        transition %i[initial] => :pending
      end
      event :complete do
        transition %i[pending initial] => :completed
      end
      event :cancel do
        transition %i[pending initial] => :canceled
      end
      event :refuse do
        transition %i[pending initial] => :refused
      end
    end

    #
    # Callbacks
    #
    before_validation :set_amount_from_order
    before_validation :set_currency_from_order
    before_validation :set_default_channel, on: :create, if: -> { channel.blank? }
    before_validation :set_return_url, on: :create, if: -> { return_url.blank? }
    before_validation :create_session_in_adyen, on: :create

    #
    # Delegations
    #
    delegate :store, :currency, to: :order

    private

    def set_amount_from_order
      self.amount ||= order&.total_minus_store_credits
    end

    def set_currency_from_order
      self.currency = order&.currency
    end

    def set_default_channel
      self.channel = AVAILABLE_CHANNELS[:web]
    end

    def set_return_url
      return if order.blank?

      self.return_url = Spree::Core::Engine.routes.url_helpers.redirect_adyen_payment_session_url(host: order.store.url_or_custom_domain)
    end

    def expiration_date_cannot_be_in_the_past_or_later_than_24_hours
      errors.add(:expires_at, "can't be in the past") if expires_at.present? && expires_at < DateTime.current

      return unless expires_at.present? && expires_at > 24.hours.from_now

      errors.add(:expires_at, "can't be more than 24 hours from now")
    end

    def currency_matches_order_currency
      errors.add(:currency, 'must match order currency') if currency != order&.currency
    end

    def amount_cannot_be_greater_than_order_total
      errors.add(:amount, "can't be greater than order total (minus store credits)") if amount > order&.total_minus_store_credits
    end

    def create_session_in_adyen
      return if adyen_id.present?

      response = payment_method.create_payment_session(amount, order, channel, return_url)
      return unless response.success?

      self.adyen_id = response.params['id']
      self.adyen_data = response.params['sessionData']
      self.expires_at = response.params['expiresAt']
    end
  end
end
