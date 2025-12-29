module SpreeAdyen
  class ApplePayDomainVerificationController < ::Spree::BaseController
    def show
      gateway = current_store.adyen_gateway

      raise ActiveRecord::RecordNotFound if gateway.nil? || !gateway.apple_developer_merchantid_domain_association.attached?

      render plain: gateway.apple_domain_association_file_content
    end
  end
end
