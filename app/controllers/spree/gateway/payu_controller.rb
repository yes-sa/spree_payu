module Spree
  class Gateway::PayuController < Spree::BaseController
    skip_before_action :verify_authenticity_token, only: :comeback
    include Spree::Core::ControllerHelpers::Order
    PAYU_SYNCABLE_STATES = %w[checkout pending].freeze

    def comeback
      payu_order_id = params.dig(:order, :orderId)

      return head :unprocessable_entity if payu_order_id.nil?

      payment = Spree::Payment.by_payu_token(payu_order_id).first

      if payment.nil?
        Sentry.capture_message("Payment not found for order: #{payu_order_id}")
        return head :unprocessable_entity
      end

      payment.payu.refresh_pay_method(params.dig(:order, :status))

      if transaction_verified?(payment, payu_order_id)
        head :ok
      else
        head :unprocessable_content
      end
    end

    def transaction_verified?(payment, payu_order_id)
      payment.payment_method.verify_transaction(
        params[:order][:status],
        payment,
        params[:order][:totalAmount],
        params[:order][:currencyCode],
        payu_order_id
      ) && payment.order.update_with_updater!
    end

    def payu_payment_syncable?(payment)
      PAYU_SYNCABLE_STATES.include?(payment.state)
    end
  end
end
