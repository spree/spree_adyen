# see: https://docs.adyen.com/partners/application-information/?tab=partner-built_0_1#application-information-fields
# some endpoints used in SpreeAdyen does not support applicationInfo (e.g. creating webhook)
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
