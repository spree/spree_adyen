module SpreeAdyen
  module PaymentSources
    class Oney < Base
      def actions
        %w[credit void capture]
      end

      def self.display_name
        'Oney'
      end
    end
  end
end
