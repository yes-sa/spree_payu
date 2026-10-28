# One PayU metafield on Spree::Payment. The instances below are the whole set,
# so an invalid key cannot be expressed in the first place.
class PayuMetafield
  NAMESPACE = 'payu'
  RESOURCE_TYPE = 'Spree::Payment'
  METAFIELD_TYPE = 'Spree::Metafields::ShortText'
  DISPLAY_ON = 'both'

  attr_reader :key, :name

  def initialize(key, name)
    @key = key
    @name = name
    freeze
  end

  TOKEN = new('token', 'Token')
  PAYMENT_URL = new('payment_url', 'Payment URL')
  PAY_METHOD = new('pay_method', 'Pay method')
  ALL = [TOKEN, PAYMENT_URL, PAY_METHOD].freeze

  private_class_method :new

  # Key accepted by Spree's set_metafield / get_metafield
  # @return [String] eg. payu.token
  def full_key
    "#{NAMESPACE}.#{key}"
  end

  def read_from(payment)
    payment.get_metafield(full_key)&.value
  end

  # Blank values are skipped, so an unknown pay method never wipes a stored one.
  def write_to(payment, value)
    return if value.blank?

    payment.set_metafield(full_key, value)
  end

  # Creates or refreshes the Spree::MetafieldDefinition backing this metafield.
  def ensure_definition!
    definition = Spree::MetafieldDefinition.find_or_initialize_by(
      resource_type: RESOURCE_TYPE, namespace: NAMESPACE, key: key
    )
    definition.name = name if definition.name.blank?
    definition.metafield_type = METAFIELD_TYPE
    definition.display_on = DISPLAY_ON
    definition.save!
    definition
  end
end
