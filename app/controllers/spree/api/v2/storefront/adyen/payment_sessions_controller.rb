module Spree
  module Api
    module V2
      module Storefront
        module Adyen
          class PaymentSessionsController < BaseController
            include Spree::Api::V2::Storefront::OrderConcern
            before_action :ensure_order
            before_action :load_payment_session, only: %i[show]

            # POST /api/v2/storefront/adyen/payment_sessions
            def create
              spree_authorize! :update, spree_current_order, order_token

              @payment_session = SpreeAdyen::PaymentSession.new(
                order: spree_current_order,
                amount: permitted_attributes[:amount],
                user: spree_current_user,
                payment_method: adyen_gateway,
                channel: permitted_attributes[:channel],
                return_url: permitted_attributes[:return_url]
              )

              if @payment_session.save
                render_serialized_payload { serialize_resource(@payment_session) }
              else
                render_error_payload(@payment_session.errors)
              end
            end

            # GET /api/v2/storefront/adyen/payment_sessions/:id
            def show
              spree_authorize! :show, spree_current_order, order_token

              render_serialized_payload { serialize_resource(@payment_session) }
            end

            private

            def permitted_attributes
              params.require(:payment_session).permit(:amount, :channel, :return_url)
            end

            def resource_serializer
              SpreeAdyen::Api::V2::Storefront::PaymentSessionSerializer
            end

            def load_payment_session
              @payment_session = spree_current_order.adyen_payment_sessions.find(params[:id])
            end
          end
        end
      end
    end
  end
end
