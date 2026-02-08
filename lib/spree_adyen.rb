require 'spree_core'
require 'spree_adyen/engine'
require 'spree_adyen/version'
require 'spree_adyen/configuration'
require 'adyen-ruby-api-library'

module SpreeAdyen
  def self.queue
    'default'
  end

  def self.version
    VERSION
  end
end
