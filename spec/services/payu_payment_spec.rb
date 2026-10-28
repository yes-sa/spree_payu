require_relative '../payu_spec_helper'

RSpec.describe PayuPayment do
  subject(:payu) { described_class.new(payment) }

  let(:stored) { {} }
  let(:payment_state) { 'checkout' }
  let(:gateway) { spy('Spree::Gateway::Payu') }

  let(:payment) do
    instance_double('Spree::Payment').tap do |payment|
      allow(payment).to receive(:state) { payment_state }
      allow(payment).to receive(:payment_method) { gateway }
      allow(payment).to receive(:get_metafield) { |key| stored.key?(key) ? double(value: stored[key]) : nil }
      allow(payment).to receive(:set_metafield) { |key, value| stored[key] = value }
    end
  end

  before { stub_const('Sentry', spy('Sentry')) }

  describe 'reading' do
    it 'exposes the payu metafields under domain names' do
      stored.merge!(
        'payu.token' => 'ORD1',
        'payu.payment_url' => 'https://payu.test/pay?x=1&lang=pl',
        'payu.pay_method' => 'BLIK'
      )

      expect(payu.token).to eq('ORD1')
      expect(payu.payment_url).to eq('https://payu.test/pay?x=1&lang=pl')
      expect(payu.pay_method).to eq('BLIK')
    end

    it 'returns nil for a metafield that was never written' do
      expect(payu.payment_url).to be_nil
    end
  end

  describe '#register' do
    it 'stores what PayU returned when the order was registered' do
      payu.register(token: 'ORD1', payment_url: 'https://payu.test/pay?lang=pl')

      expect(stored).to eq('payu.token' => 'ORD1', 'payu.payment_url' => 'https://payu.test/pay?lang=pl')
    end
  end

  describe '#refresh_pay_method' do
    context 'when nothing is stored yet' do
      it 'fetches and stores the pay method, whatever the status' do
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return('Klarna')

        payu.refresh_pay_method('WAITING_FOR_CONFIRMATION')

        expect(payu.pay_method).to eq('Klarna')
      end

      it 'stores nothing when PayU does not know the method yet, and retries later' do
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return(nil, 'BLIK')

        payu.refresh_pay_method('PENDING')
        expect(payu.pay_method).to be_nil

        payu.refresh_pay_method('PENDING')
        expect(payu.pay_method).to eq('BLIK')
      end

      it 'asks PayU using the token it already holds' do
        stored['payu.token'] = 'ORD1'
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return('BLIK')

        payu.refresh_pay_method('PENDING')

        expect(gateway).to have_received(:fetch_transaction_pay_method).with('ORD1')
      end
    end

    context 'when a pay method is already stored' do
      before { stored['payu.pay_method'] = 'Card' }

      it 'leaves it alone on a non terminal status, without calling PayU' do
        payu.refresh_pay_method('PENDING')

        expect(payu.pay_method).to eq('Card')
        expect(gateway).not_to have_received(:fetch_transaction_pay_method)
      end

      it 'refreshes it on the terminal notification it actually processes' do
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return('Apple Pay')

        payu.refresh_pay_method('COMPLETED')

        expect(payu.pay_method).to eq('Apple Pay')
      end

      it 'refreshes it on CANCELED too' do
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return('Google Pay')

        payu.refresh_pay_method('CANCELED')

        expect(payu.pay_method).to eq('Google Pay')
      end

      context 'when the payment has already left checkout' do
        let(:payment_state) { 'completed' }

        it 'ignores a duplicate terminal notification, without calling PayU' do
          payu.refresh_pay_method('COMPLETED')

          expect(payu.pay_method).to eq('Card')
          expect(gateway).not_to have_received(:fetch_transaction_pay_method)
        end
      end
    end

    context 'when storing blows up' do
      it 'reports to Sentry instead of stopping the transaction from being verified' do
        allow(gateway).to receive(:fetch_transaction_pay_method).and_return('BLIK')
        allow(payment).to receive(:set_metafield).and_raise(StandardError, 'metafield definition invalid')

        expect { payu.refresh_pay_method('COMPLETED') }.not_to raise_error
        expect(Sentry).to have_received(:capture_exception).once
      end
    end
  end
end
