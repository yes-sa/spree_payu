# A payment seen through the PayU integration. Reads and writes the payu
# metafields and owns the rule for when the pay method is final.
class PayuPayment
  # Statuses on which PayU knows the final pay method
  TERMINAL_STATUSES = %w[COMPLETED CANCELED].freeze

  def initialize(payment)
    @payment = payment
  end

  def token
    PayuMetafield::TOKEN.read_from(payment)
  end

  def payment_url
    PayuMetafield::PAYMENT_URL.read_from(payment)
  end

  def pay_method
    PayuMetafield::PAY_METHOD.read_from(payment)
  end

  # Stores what PayU returned when the order was registered.
  def register(token:, payment_url:)
    PayuMetafield::TOKEN.write_to(payment, token)
    PayuMetafield::PAYMENT_URL.write_to(payment, payment_url)
    self
  end

  # Fetches the pay method from PayU when none is stored, or when this is the
  # notification carrying the final one. A bookkeeping failure here must never
  # stop the transaction from being verified.
  def refresh_pay_method(payu_status)
    return unless refresh_pay_method?(payu_status)

    PayuMetafield::PAY_METHOD.write_to(payment, fetch_pay_method)
  rescue StandardError => e
    Sentry.capture_exception(e)
  end

  private

  attr_reader :payment

  def refresh_pay_method?(payu_status)
    return true if pay_method.blank?

    payment.state == 'checkout' && TERMINAL_STATUSES.include?(payu_status)
  end

  def fetch_pay_method
    payment.payment_method.fetch_transaction_pay_method(token)
  end
end
