module SpreeAdyen
  module PaymentSources
    class Scalapay < Base
      def actions
        %w[credit void]
      end

      def self.display_name
        'Scalapay'
      end
    end
  end
end
