Spree::Core::Engine.add_routes do
  # Apple Pay domain verification certificate for Apple Pay
  get '/.well-known/apple-developer-merchantid-domain-association' => '/spree_adyen/apple_pay_domain_verification#show'

  # redirection after redirect flow payment (f.e. klarna)
  # checking the redirect result status in frontend
  get '/adyen/payment_sessions/redirect', to: '/spree_adyen/payment_sessions#redirect',
                                           as: :redirect_adyen_payment_session,
                                           controller: '/spree_adyen/payment_sessions'

  # redirection after non-redirect flow payment for checking payment session result (f.e. credit cards)
  # checking the session result status in frontend
  get '/adyen/payment_sessions', to: '/spree_adyen/payment_sessions#show',
                                     as: :adyen_payment_session,
                                     controller: '/spree_adyen/payment_sessions'

  post '/adyen/webhooks', to: '/spree_adyen/webhooks#create', controller: '/spree_adyen/webhooks'

  # Storefront API
  namespace :api, defaults: { format: 'json' } do
    namespace :v2 do
      namespace :storefront do
        namespace :adyen do
          resources :payment_sessions, only: %i[show create]
        end
      end
    end
  end
end
