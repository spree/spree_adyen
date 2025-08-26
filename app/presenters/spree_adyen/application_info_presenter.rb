module SpreeAdyen
  class ApplicationInfoPresenter
    def to_h
      {
        applicationInfo: {
          externalPlatform: {
            name: 'Spree Commerce',
            version: Spree.version,
            integrator: 'Spree Adyen'
          }
        }
      }
    end
  end
end
