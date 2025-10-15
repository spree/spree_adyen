module SpreeAdyen
  module Api
    module V2
      module Storefront
        class PaymentSessionSerializer < ::Spree::Api::V2::BaseSerializer
          set_type :adyen_payment_session

          attributes :adyen_id, :amount, :currency, :adyen_data, :status, :expires_at, :channel, :return_url

          attribute :client_key do |object|
            object.payment_method.preferred_client_key
          end

          belongs_to :order, serializer: ::Spree::Api::Dependencies.storefront_cart_serializer.constantize
          belongs_to :payment_method, serializer: ::Spree::Api::Dependencies.storefront_payment_method_serializer.constantize
          belongs_to :user, serializer: ::Spree::Api::Dependencies.storefront_user_serializer.constantize
        end
      end
    end
  end
end
