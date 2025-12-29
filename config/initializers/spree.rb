# Uncomment lines below to add your own custom business logic
# such as promotions, shipping methods, etc.
Rails.application.config.after_initialize do
  # Rails.application.config.spree.shipping_methods << Spree::ShippingMethods::SuperExpensiveNotVeryFastShipping
  Rails.application.config.spree.payment_methods << SpreeAdyen::Gateway

  # Rails.application.config.spree.calculators.tax_rates << Spree::TaxRates::FinanceTeamForcedMeToCodeThis

  # Rails.application.config.spree.stock_splitters << Spree::Stock::Splitters::SecretLogicSplitter

  # Rails.application.config.spree.adjusters << Spree::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # Rails.application.config.spree.calculators.promotion_actions_create_adjustments << Spree::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments << Spree::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # Rails.application.config.spree.promotions.rules << Spree::Promotions::Rules::OnlyForVIPCustomers
  # Rails.application.config.spree.promotions.actions << Spree::Promotions::Actions::GiftWithPurchase

  # Rails.application.config.spree.taxon_rules << Spree::TaxonRules::ProductsWithColor

  # Rails.application.config.spree.exports << Spree::Exports::Payments
  # Rails.application.config.spree.reports << Spree::Reports::MassivelyOvercomplexReportForCfo

  # Themes and page builder
  # Rails.application.config.spree.themes << Spree::Themes::NewShinyTheme
  # Rails.application.config.spree.theme_layout_sections << Spree::PageSections::SuperImportantCeoBio
  # Rails.application.config.spree.page_sections << Spree::PageSections::ContactFormToGetInTouch
  # Rails.application.config.spree.page_blocks << Spree::PageBlocks::BigRedButtonToCallSales

  # Storefront partials
  if Rails.application.config.respond_to?(:spree_storefront)
    Rails.application.config.spree_storefront.head_partials << 'spree_adyen/head'
  end
end
