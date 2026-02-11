module SpreeAdyen
  class WebhooksController < ActionController::API
    include Spree::Core::ControllerHelpers::Store

    before_action :validate_hmac!

    def create
      SpreeAdyen::Webhooks::HandleEvent.new(event_payload: webhook_params).call

      head :ok
    end

    private

    def validate_hmac!
      if hmac_validator_class.nil?
        Rails.logger.error("[SpreeAdyen]: No HMAC validator for #{event_code}")
        head :unauthorized
        return
      end

      validator = hmac_validator_class.new(
        request: request,
        params: webhook_params,
        gateway: current_store.adyen_gateway
      )

      return if validator.call

      Rails.logger.error("[SpreeAdyen]: Failed to validate hmac for #{event_code}")
      head :unauthorized
    end

    def hmac_validator_class
      SpreeAdyen.hmac_validators[event_code]
    end

    def event_code
      webhook_params.dig('notificationItems', 0, 'NotificationRequestItem', 'eventCode') || webhook_params['type']
    end

    def webhook_params
      @webhook_params ||= params.require(:webhook).permit!
    end
  end
end
