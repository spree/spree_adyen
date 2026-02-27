module SpreeAdyen
  class Gateway < ::Spree::Gateway
    module PaymentSessions
      extend ActiveSupport::Concern

      def session_required?
        true
      end

      def payment_session_class
        Spree::PaymentSessions::Adyen
      end

      # Creates a new Adyen payment session via the Adyen Sessions API
      # and persists a Spree::PaymentSessions::Adyen record.
      #
      # @param order [Spree::Order] the order to create a session for
      # @param amount [BigDecimal, nil] the amount (defaults to order total minus store credits)
      # @param external_data [Hash] additional data (e.g., channel, return_url)
      # @return [Spree::PaymentSessions::Adyen] the created payment session record
      def create_payment_session(order:, amount: nil, external_data: {})
        total = amount.presence || order.total_minus_store_credits
        channel = external_data[:channel] || external_data['channel'] || Spree::PaymentSessions::Adyen::AVAILABLE_CHANNELS[:web]
        return_url = external_data[:return_url] || external_data['return_url'] || default_return_url(order)

        response = create_adyen_session(total, order, channel, return_url)

        payment_session_class.create!(
          order: order,
          payment_method: self,
          amount: total,
          currency: order.currency,
          status: 'pending',
          external_id: response.params['id'],
          customer: order.user,
          expires_at: response.params['expiresAt'],
          external_data: {
            'session_data' => response.params['sessionData'],
            'channel' => channel,
            'return_url' => return_url
          }
        )
      end

      # Updates an existing payment session amount.
      #
      # @param payment_session [Spree::PaymentSessions::Adyen] the session to update
      # @param amount [BigDecimal, nil] new amount
      # @param external_data [Hash] additional data to merge
      def update_payment_session(payment_session:, amount: nil, external_data: {})
        attrs = {}
        attrs[:amount] = amount if amount.present?

        if external_data.present?
          attrs[:external_data] = (payment_session.external_data || {}).merge(external_data.stringify_keys)
        end

        payment_session.update!(attrs) if attrs.any?
      end

      # Completes a payment session by checking the session result with Adyen
      # and transitioning the session + order accordingly.
      #
      # @param payment_session [Spree::PaymentSessions::Adyen] the session to complete
      # @param params [Hash] must include :session_result
      def complete_payment_session(payment_session:, params: {})
        session_result = params[:session_result] || params['session_result']

        response = payment_session_result(payment_session.external_id, session_result)
        status = response.params.fetch('status')

        payment_session.order.with_lock do
          payment = payment_session.order.payments.where(
            payment_method: payment_session.payment_method,
            response_code: payment_session.external_id
          ).first_or_initialize

          payment.update!(amount: payment_session.amount, skip_source_requirement: true)
          payment.started_processing! if payment.checkout?

          case status
          when 'completed'
            payment_session.complete if payment_session.can_complete?
            payment.confirm!
            Spree::Dependencies.checkout_complete_service.constantize.call(order: payment_session.order) unless payment_session.order.completed?
          when 'canceled'
            payment.void! if payment.can_void?
            payment_session.cancel if payment_session.can_cancel?
          when 'refused', 'expired'
            payment.failure! unless payment.failed?
            payment_session.fail if payment_session.can_fail?
          when 'paymentPending'
            payment_session.process if payment_session.can_process?
          else
            Rails.error.unexpected('Unexpected Adyen payment status', context: { order_id: payment_session.order.id, status: status },
                                                                      source: 'spree_adyen')
          end
        end
      end

      private

      def default_return_url(order)
        Spree::Core::Engine.routes.url_helpers.redirect_adyen_payment_session_url(host: order.store.url_or_custom_domain)
      end
    end
  end
end
