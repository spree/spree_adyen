module SpreeAdyen
  module CustomDomainDecorator
    def self.prepended(base)
      base.after_commit :add_adyen_allowed_origin
    end

    def add_adyen_allowed_origin
      return if store.adyen_gateway.blank?

      SpreeAdyen::AddAllowedOriginJob.perform_later(id, store.adyen_gateway.id, 'custom_domain')
    end
  end
end

Spree::CustomDomain.prepend(SpreeAdyen::CustomDomainDecorator) if defined?(Spree::CustomDomain)
