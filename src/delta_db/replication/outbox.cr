# src/delta_db/replication/outbox.cr
module DeltaDB
  module Replication
    class Outbox
      def initialize(@storage : Storage)
      end

      def append(pack : ReplicationPack) : ReplicationOutboxEntry
        entry = ReplicationOutboxEntry.new(pack)
        @storage.insert_replication_outbox(entry)
        entry
      end

      def pending : Array(ReplicationOutboxEntry)
        @storage.replication_outbox_entries(ReplicationOutboxState::Pending)
      end

      def size : Int32
        @storage.replication_outbox_size
      end

      def acknowledge(id : String) : Nil
        @storage.update_replication_outbox_state(id, ReplicationOutboxState::Acknowledged)
      end

      def fail(id : String, message : String) : Nil
        @storage.update_replication_outbox_state(id, ReplicationOutboxState::Failed, message)
      end

      def retry(id : String) : Nil
        @storage.update_replication_outbox_state(id, ReplicationOutboxState::Pending)
      end
    end
  end
end
