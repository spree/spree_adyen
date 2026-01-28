# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'spree_adyen/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_adyen'
  s.version     = SpreeAdyen::VERSION
  s.summary     = "Spree Commerce Adyen Extension"
  s.required_ruby_version = '>= 3.0'

  s.author    = 'Vendo Connect Inc., Vendo Sp. z o.o.'
  s.email     = 'hello@spreecommerce.org'
  s.homepage  = 'https://github.com/spree/spree_adyen'
  s.license = 'AGPL-3.0-or-later'

  s.files        = Dir["{app,config,db,lib,vendor}/**/*", "LICENSE.md", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  spree_version = '>= 5.1.4'
  s.add_dependency 'spree', spree_version
  s.add_dependency 'spree_extension'

  s.add_dependency 'adyen-ruby-api-library', '~> 10.3'

  s.add_development_dependency 'spree_dev_tools'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'pry-rails'
  s.add_development_dependency 'timecop'
end
