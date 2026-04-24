module SpreeAdyen
  module RefundDecorator
    ADYEN_REFUND_STATUS_METAFIELD_KEY = 'adyen.refund_status'.freeze
    ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY = 'adyen.refund_error_message'.freeze

    ADYEN_REFUND_STATUS_PENDING = 'pending'.freeze
    ADYEN_REFUND_STATUS_SUBMITTED = 'submitted'.freeze
    ADYEN_REFUND_STATUS_REJECTED = 'rejected'.freeze

    def adyen_refund_status
      get_metafield(ADYEN_REFUND_STATUS_METAFIELD_KEY)&.value || ADYEN_REFUND_STATUS_PENDING
    end

    def adyen_refund_error_message
      get_metafield(ADYEN_REFUND_ERROR_MESSAGE_METAFIELD_KEY)&.value
    end
  end
end

Spree::Refund.prepend(SpreeAdyen::RefundDecorator)
