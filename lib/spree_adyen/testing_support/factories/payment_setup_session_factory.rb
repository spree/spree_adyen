FactoryBot.define do
  factory :adyen_payment_setup_session, class: 'Spree::PaymentSetupSessions::Adyen' do
    sequence(:external_id) { |n| "CS_setup_#{n}" }
    status { 'pending' }
    payment_method { create(:adyen_gateway) }
    customer factory: :user

    external_data do
      {
        'session_data' => 'a very long session data string',
        'channel' => 'Web'
      }
    end
  end
end
