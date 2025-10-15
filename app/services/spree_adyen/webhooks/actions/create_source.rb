module SpreeAdyen
  module Webhooks
    module Actions
      class CreateSource
        CREDIT_CARD_SOURCES = %i[
          accel
          amex
          jcb
          carnet
          cartebancaire
          cup
          diners
          discover
          eftpos_australia
          elo
          googlepay
          maestro
          maestro_usa
          mc
          visa
        ].freeze

        SOURCE_KLASS_MAP = {
          affirm: SpreeAdyen::PaymentSources::Affirm,
          alipay: SpreeAdyen::PaymentSources::Alipay,
          bacs: SpreeAdyen::PaymentSources::Bacs,
          bankTransfer_IBAN: SpreeAdyen::PaymentSources::BankTransfer,
          klarna_b2b: SpreeAdyen::PaymentSources::Billie,
          blik: SpreeAdyen::PaymentSources::Blik,
          clearpay: SpreeAdyen::PaymentSources::Clearpay,
          eps: SpreeAdyen::PaymentSources::Eps,
          ideal: SpreeAdyen::PaymentSources::Ideal,
          facilypay_3x: SpreeAdyen::PaymentSources::Oney,
          facilypay_4x: SpreeAdyen::PaymentSources::Oney,
          facilypay_6x: SpreeAdyen::PaymentSources::Oney,
          facilypay_10x: SpreeAdyen::PaymentSources::Oney,
          facilypay_12x: SpreeAdyen::PaymentSources::Oney,
          scalapay_3x: SpreeAdyen::PaymentSources::Scalapay,
          klarna: SpreeAdyen::PaymentSources::Klarna,
          klarna_account: SpreeAdyen::PaymentSources::Klarna,
          klarna_paynow: SpreeAdyen::PaymentSources::Klarna,
          klarna_paylater: SpreeAdyen::PaymentSources::Klarna,
          klarna_payovertime: SpreeAdyen::PaymentSources::Klarna,
          onlineBanking_CZ: SpreeAdyen::PaymentSources::OnlineBankingCzechRepublic,
          onlineBanking_PL: SpreeAdyen::PaymentSources::OnlineBankingPoland,
          paybybank: SpreeAdyen::PaymentSources::PayByBank,
          paypal: SpreeAdyen::PaymentSources::Paypal,
          paypo: SpreeAdyen::PaymentSources::Paypo,
          paysafecard: SpreeAdyen::PaymentSources::Paysafecard,
          ratepay_directdebit: SpreeAdyen::PaymentSources::RatePayDirectDebit,
          riverty: SpreeAdyen::PaymentSources::Riverty,
          samsungpay: SpreeAdyen::PaymentSources::SamsungPay,
          sepadirectdebit: SpreeAdyen::PaymentSources::SepaDirectDebit,
          trustly: SpreeAdyen::PaymentSources::Trustly,
          wechatpaySDK: SpreeAdyen::PaymentSources::WechatPay,
          wechatpayQR: SpreeAdyen::PaymentSources::WechatPay,
          ach: SpreeAdyen::PaymentSources::AchDirectDebit,
          afterpaytouch: SpreeAdyen::PaymentSources::Afterpay,
          afterpaytouch_US: SpreeAdyen::PaymentSources::CashAppAfterpay,
          alipay_hk: SpreeAdyen::PaymentSources::AlipayHk,
          alma: SpreeAdyen::PaymentSources::Alma,
          ancv: SpreeAdyen::PaymentSources::Ancv,
          atome: SpreeAdyen::PaymentSources::Atome,
          benefit: SpreeAdyen::PaymentSources::Benefit,
          bcmc: SpreeAdyen::PaymentSources::Bancontact,
          bcmc_mobile: SpreeAdyen::PaymentSources::Bancontact,
          bizum: SpreeAdyen::PaymentSources::Bizum,
          boleto: SpreeAdyen::PaymentSources::Boleto,
          cashapp: SpreeAdyen::PaymentSources::Cashapp,
          doku_alfamart: SpreeAdyen::PaymentSources::Doku,
          doku_indomaret: SpreeAdyen::PaymentSources::Doku,
          dana: SpreeAdyen::PaymentSources::Dana,
          duitnow: SpreeAdyen::PaymentSources::Duitnow,
          fastlane: SpreeAdyen::PaymentSources::Fastlane,
          molpay_ebanking_fpx_MY: SpreeAdyen::PaymentSources::Fpx,
          gcash: SpreeAdyen::PaymentSources::Gcash,
          givex: SpreeAdyen::PaymentSources::GiftCards,
          genericgiftcard: SpreeAdyen::PaymentSources::GiftCards,
          valuelink: SpreeAdyen::PaymentSources::GiftCards,
          svs: SpreeAdyen::PaymentSources::GiftCards,
          giropay: SpreeAdyen::PaymentSources::Giropay,
          grabpay_MY: SpreeAdyen::PaymentSources::Grabpay,
          grabpay_PH: SpreeAdyen::PaymentSources::Grabpay,
          grabpay_SG: SpreeAdyen::PaymentSources::Grabpay
        }.freeze

        def initialize(event:, payment_method:, user:)
          @event = event
          @payment_method = payment_method
          @user = user
        end

        def call
          if event.payment_method_reference.in?(CREDIT_CARD_SOURCES)
            find_or_create_credit_card
          else
            find_or_create_source
          end
        end

        def find_or_create_source
          source_klass_factory.find_or_create_by(payment_method: payment_method, user: user)
        end

        def find_or_create_credit_card
          SpreeAdyen::Webhooks::Actions::FindOrCreateCreditCard.new(
            event: event,
            gateway: payment_method,
            user: user
          ).call
        end

        private

        attr_reader :event, :payment_method, :user

        delegate :payment_method_reference, to: :event

        def source_klass_factory
          SOURCE_KLASS_MAP[event.payment_method_reference] ||= SpreeAdyen::PaymentSources::Unknown
        end
      end
    end
  end
end
