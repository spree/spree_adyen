module SpreeAdyen
  class AddAllowedOriginJob < SpreeAdyen::BaseJob
    def perform(record_id, gateway_id, klass_type = 'store')
      @klass_type = klass_type.to_s
      return unless klass

      record = klass.find(record_id)
      gateway = SpreeAdyen::Gateway.find(gateway_id)

      SpreeAdyen::Gateways::AddAllowedOrigin.new(record, gateway).call
    end

    private

    def klass
      @klass ||= case @klass_type
                 when 'store' then Spree::Store
                 when 'custom_domain' then defined?(Spree::CustomDomain) ? Spree::CustomDomain : nil
                 else
                   Rails.error.unexpected("Unexpected klass_type: #{@klass_type}")
                 end
    end
  end
end
