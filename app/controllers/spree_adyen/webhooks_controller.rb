module SpreeAdyen
  class WebhooksController < Spree::BaseController
    skip_before_action :verify_authenticity_token
    before_action :validate_hmac!

    def create
      SpreeAdyen::Webhooks::HandleEvent.new(event_payload: webhook_params).call

      head :ok
    end

    private

    def validate_hmac!
      event = SpreeAdyen::Webhooks::Event.new(event_data: webhook_params)
      return if hmac_keys.any? do |hmac_key|
        Adyen::Utils::HmacValidator.new.valid_webhook_hmac?(
          webhook_params.dig('notificationItems', 0, 'NotificationRequestItem'),
          hmac_key
        )
      end

      Rails.logger.error("[SpreeAdyen][#{event.id}]: Failed to validate hmac")

      head :unauthorized
    end

    def hmac_keys
      @hmac_keys ||= [
        current_store.adyen_gateway.preferred_hmac_key,
        current_store.adyen_gateway.previous_hmac_key
      ].compact
    end

    def webhook_params
      params.require(:webhook).permit(
        :live,
        notificationItems: [{ NotificationRequestItem: {} }]
      )
    end
  end
end
