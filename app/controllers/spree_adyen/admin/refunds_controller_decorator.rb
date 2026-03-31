module SpreeAdyen
  module Admin
    module RefundsControllerDecorator
      def retry
        result = SpreeAdyen::Refunds::Retry.call(refund: @refund)

        if result.success?
          flash[:success] = Spree.t(:refund_retry_submitted)
        else
          flash[:error] = result.value
        end

        redirect_to spree.edit_admin_order_path(@refund.payment.order)
      end
    end
  end
end

Spree::Admin::RefundsController.prepend(SpreeAdyen::Admin::RefundsControllerDecorator) if defined?(Spree::Admin::RefundsController)
