module Spree
  module Api
    module V2
      module Storefront
        module Adyen
          class BaseController < ::Spree::Api::V2::BaseController
            before_action :require_adyen_gateway

            def require_adyen_gateway
              render_error_payload('Adyen gateway is not present') unless adyen_gateway
            end

            def adyen_gateway
              @adyen_gateway ||= current_store.adyen_gateway
            end
          end
        end
      end
    end
  end
end
