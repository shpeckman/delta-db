# src/delta_db/replication/outbox.cr
module DeltaDB
  module Replication
    class Outbox
      def initialize(@storage : Storage)
      end

      def append(pack : Pack) : Entry
        entry = Entry.new(pack)
        @storage.insert_replication_outbox(entry)
        entry
      end

      def pending : Array(Entry)
        @storage.replication_outbox_entries(Entry::State::Pending)
      end

      def size : Int32
        @storage.replication_outbox_size
      end

      def acknowledge(id : String) : Nil
        @storage.update_replication_outbox_state(id, Entry::State::Acknowledged)
      end

      def fail(id : String, message : String) : Nil
        @storage.update_replication_outbox_state(id, Entry::State::Failed, message)
      end

      def retry(id : String) : Nil
        @storage.update_replication_outbox_state(id, Entry::State::Pending)
      end
    end
  end
end
