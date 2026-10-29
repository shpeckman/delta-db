# src/delta_db/delta_run.cr
module DeltaDB
  struct DeltaRun
    getter actor : ReplicaId
    getter timestamp : Lamport
    getter delta_ids : Array(DeltaId)

    def initialize(@actor : ReplicaId, @timestamp : Lamport, @delta_ids : Array(DeltaId))
    end
  end
end
