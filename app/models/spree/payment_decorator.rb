
module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.after_create :create_payu_token
      base.scope :by_payu_token, ->(token) {
        with_metafield_key_value(PayuMetafield::TOKEN.full_key, token)
      }
    end

    def payu
      @payu ||= PayuPayment.new(self)
    end

    private

    def create_payu_token
      return if not self.payment_method.is_a? Gateway::Payu

      payment_method.register_order(self.order, self.id, self.payment_method.id)
    end
  end
end

::Spree::Payment.prepend(Spree::PaymentDecorator)
