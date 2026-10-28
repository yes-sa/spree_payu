namespace :spree_payu do
  namespace :metafields do
    desc 'Creates the PayU metafield definitions and backfills them from public_metadata'
    task setup: %i[create backfill]

    desc 'Creates the short text metafield definitions used by PayU payments'
    task create: :environment do
      PayuMetafield::ALL.each do |metafield|
        definition = metafield.ensure_definition!
        state = definition.previously_new_record? ? 'created' : 'updated'

        puts "#{state} #{definition.full_key} (#{definition.metafield_type}) for #{definition.resource_type}"
      end
    end

    desc 'Copies PayU data from public_metadata of existing payments into the payu metafields'
    task backfill: :environment do
      payu_types = [
        Spree::Gateway::Payu,
        Spree::Gateway::PayuInstallment,
        Spree::Gateway::Paypo
      ].map(&:name)

      payments = Spree::Payment.
                 where(payment_method_id: Spree::PaymentMethod.where(type: payu_types).select(:id)).
                 where.not(public_metadata: nil)

      backfilled = 0
      cleaned = 0
      skipped = 0
      failed = 0

      payments.find_each do |payment|
        metadata = payment.public_metadata
        present = PayuMetafield::ALL.select { |metafield| metadata.key?(metafield.key) }

        if present.empty?
          skipped += 1
          next
        end

        written = []
        removable = []

        # One payment moves as a whole - a failure halfway through must not leave it
        # with a token metafield and no payment_url, which would break the redirect.
        Spree::Payment.transaction do
          present.each do |metafield|
            value = metadata[metafield.key]

            # Nothing to migrate - an empty copy of our own key is just leftover.
            if value.blank?
              removable << metafield.key
              next
            end

            # A metafield already holding a value wins, the copy is stale. Keeps the
            # task re-runnable and never overwrites data written after the migration.
            if metafield.read_from(payment).present?
              removable << metafield.key
              next
            end

            metafield.write_to(payment, value)

            # The copy is dropped only once the metafield reads the value back.
            if metafield.read_from(payment) == value.to_s.strip
              written << metafield.key
              removable << metafield.key
            else
              warn "payment #{payment.number} => #{metafield.full_key} did not read back, public_metadata kept"
            end
          end

          # Only our own keys are dropped, anything else stored there stays untouched.
          # update_columns on purpose - a data migration must not trip validations or
          # callbacks of long finished payments.
          payment.update_columns(public_metadata: metadata.except(*removable)) if removable.any?
        end

        # Counted only once the transaction above has committed.
        backfilled += 1 if written.any?
        cleaned += 1 if removable.any?

        if written.any? || removable.any?
          puts "payment #{payment.number}: wrote [#{written.join(' ')}] removed from public_metadata [#{removable.join(' ')}]"
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        failed += 1
        warn "payment #{payment.number} failed => #{e.message}"
      end

      puts "backfilled #{backfilled} payment(s), cleaned #{cleaned}, skipped #{skipped}, failed #{failed}"
    end
  end
end
