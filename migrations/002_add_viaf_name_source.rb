# Adds 'viaf' as a value of the name_source enumeration so that VIAF cluster
# identifiers (Wikidata P214) imported from Wikidata are attributed to VIAF
# rather than the generic 'local' source. name_source backs both
# agent_record_identifier.source and the agent name source field.
#
# Self-contained and idempotent: it inserts the value only if missing and does
# not depend on the core migration helper load path.
Sequel.migration do
  up do
    enum  = "name_source"
    value = "viaf"

    e_id = self[:enumeration].filter(:name => enum).get(:id)
    next unless e_id

    v_id = self[:enumeration_value].filter(:enumeration_id => e_id, :value => value).get(:id)
    unless v_id
      $stderr.puts("Adding '#{value}' to #{enum} enumeration")
      pos = (self[:enumeration_value].filter(:enumeration_id => e_id).max(:position) || 0) + 1
      self[:enumeration_value].insert(:enumeration_id => e_id, :value => value, :position => pos)
    end
  end

  down do
    # Intentionally left as a no-op: removing an enumeration value that may be
    # in use by existing records is unsafe.
  end
end
