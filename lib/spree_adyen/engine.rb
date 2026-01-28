module SpreeAdyen
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_adyen'

    config.eager_load_paths += %W(#{config.root}/app/services)
    config.generators do |g| # use rspec for tests
      g.test_framework :rspec
    end

    initializer 'spree_adyen.environment', before: :load_config_initializers do |_app|
      SpreeAdyen::Config = SpreeAdyen::Configuration.new
    end

    initializer 'spree_adyen.assets' do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join('app/javascript')
        app.config.assets.paths << root.join('vendor/javascript')
        app.config.assets.paths << root.join('vendor/stylesheets')
        app.config.assets.precompile += %w[spree_adyen_manifest]
      end
    end

    initializer 'spree_adyen.importmap', before: 'importmap' do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join('config/importmap.rb')
        # https://github.com/rails/importmap-rails?tab=readme-ov-file#sweeping-the-cache-in-development-and-test
        app.config.importmap.cache_sweepers << root.join('app/javascript')
      end
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
