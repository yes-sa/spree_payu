require_relative '../payu_spec_helper'

RSpec.describe PayuMetafield do
  let(:payment) { instance_double('Spree::Payment') }

  describe 'the set of metafields' do
    it 'covers exactly the three payu keys' do
      expect(described_class::ALL.map(&:full_key)).to eq(%w[payu.token payu.payment_url payu.pay_method])
    end

    it 'cannot be extended at runtime' do
      expect { described_class.new('whatever', 'Whatever') }.to raise_error(NoMethodError)
    end

    it 'freezes its instances' do
      expect(described_class::ALL).to all(be_frozen)
    end
  end

  describe '#read_from' do
    it 'returns the stored value' do
      allow(payment).to receive(:get_metafield).with('payu.token').and_return(double(value: 'ORD1'))

      expect(described_class::TOKEN.read_from(payment)).to eq('ORD1')
    end

    it 'returns nil when the payment has no such metafield' do
      allow(payment).to receive(:get_metafield).with('payu.pay_method').and_return(nil)

      expect(described_class::PAY_METHOD.read_from(payment)).to be_nil
    end
  end

  describe '#write_to' do
    it 'stores the value under the full key' do
      expect(payment).to receive(:set_metafield).with('payu.pay_method', 'BLIK')

      described_class::PAY_METHOD.write_to(payment, 'BLIK')
    end

    it 'skips blank values so a stored value is never wiped' do
      expect(payment).not_to receive(:set_metafield)

      described_class::PAY_METHOD.write_to(payment, nil)
      described_class::PAY_METHOD.write_to(payment, '')
    end
  end

  describe '#ensure_definition!' do
    let(:definition) do
      Struct.new(:name, :metafield_type, :display_on, :saved) do
        def save!
          self.saved = true
        end
      end.new
    end

    before do
      stub_const('Spree::MetafieldDefinition', spy('Spree::MetafieldDefinition'))
      allow(Spree::MetafieldDefinition).to receive(:find_or_initialize_by).and_return(definition)
    end

    it 'looks the definition up by resource type, namespace and key' do
      described_class::PAY_METHOD.ensure_definition!

      expect(Spree::MetafieldDefinition).to have_received(:find_or_initialize_by).with(
        resource_type: 'Spree::Payment', namespace: 'payu', key: 'pay_method'
      )
    end

    it 'saves it as a short text metafield visible on both ends' do
      described_class::PAY_METHOD.ensure_definition!

      expect(definition.metafield_type).to eq('Spree::Metafields::ShortText')
      expect(definition.display_on).to eq('both')
      expect(definition.saved).to be(true)
    end

    it 'names a freshly built definition' do
      described_class::PAYMENT_URL.ensure_definition!

      expect(definition.name).to eq('Payment URL')
    end

    it 'leaves a name somebody already set in the admin panel' do
      definition.name = 'Link do platnosci'

      described_class::PAYMENT_URL.ensure_definition!

      expect(definition.name).to eq('Link do platnosci')
    end
  end
end
