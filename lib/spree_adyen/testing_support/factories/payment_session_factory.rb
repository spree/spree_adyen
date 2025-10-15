FactoryBot.define do
  factory :payment_session, class: SpreeAdyen::PaymentSession do
    sequence(:adyen_id) { |n| "pi_#{n}" }
    adyen_data { 'a very long string' }
    amount { order.total_minus_store_credits }
    currency { order.currency }
    channel { 'Web' }
    status { 'initial' }
    expires_at { 1.hour.from_now }
    payment_method { create(:adyen_gateway) }

    association :user
    association :order, factory: :order_with_line_items

    trait :expired do
      expires_at { 1.hour.ago }
      skip_expiration_date_validation { true }
    end

    trait :initial do
      status { 'initial' }
    end

    trait :pending do
      status { 'pending' }
    end

    trait :completed do
      status { 'completed' }
    end

    trait :outdated do
      status { 'outdated' }
    end

    trait :canceled do
      status { 'canceled' }
    end
  end
end
