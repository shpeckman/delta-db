# src/delta_db/storage/run.cr
module DeltaDB
  class Storage
    struct Run
      getter actor : ReplicaId
      getter timestamp : Lamport
      getter delta_ids : Array(DeltaId)

      def initialize(@actor : ReplicaId, @timestamp : Lamport, @delta_ids : Array(DeltaId))
      end
    end
  end
end
