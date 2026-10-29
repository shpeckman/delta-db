# src/delta_db/replication/outbox/entry.cr
module DeltaDB
  module Replication
    class Outbox
      class Entry
        enum State
          Pending
          Sending
          Acknowledged
          Failed
        end

        getter pack : ReplicationPack
        property state : ReplicationOutboxState
        property last_error : String?

        def initialize(@pack : ReplicationPack, @state : ReplicationOutboxState = ReplicationOutboxState::Pending, @last_error : String? = nil)
        end

        def id : String
          @pack.id
        end
      end
    end
  end
end
