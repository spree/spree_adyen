FactoryBot.define do
  factory :adyen_gateway, parent: :payment_method, class: SpreeAdyen::Gateway do
    name { 'Adyen' }
    type { 'SpreeAdyen::Gateway' }

    skip_auto_configuration { true }
    skip_api_key_validation { true }

    preferences do
      {
        api_key: 'secret',
        merchant_account: 'SpreeCommerceECOM',
        hmac_key: 'secret123',
        client_key: 'client123',
        webhook_id: 'webhook123'
      }
    end

    trait :with_apple_domain_association_file do
      transient do
        apple_domain_association_file_path do
          File.join(SpreeAdyen::Engine.root, 'spec', 'fixtures', 'files', 'apple-domain-association-file.txt')
        end
      end

      apple_developer_merchantid_domain_association { Rack::Test::UploadedFile.new(apple_domain_association_file_path) }
    end
  end
end
