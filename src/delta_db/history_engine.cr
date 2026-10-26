module DeltaDB
  # A run of deltas from a single actor/timestamp — a batch in the history DAG.
  #
  # Clean-room reconstruction of `deltadb::history::delta_run` / `DeltaRun`
  # (fields `actor`, `timestamp`, `delta_ids` recovered from the deserializer).
  struct DeltaRun
    getter actor : ReplicaId
    getter timestamp : Lamport
    getter delta_ids : Array(DeltaId)

    def initialize(@actor : ReplicaId, @timestamp : Lamport, @delta_ids : Array(DeltaId))
    end
  end

  # A record in the history: a versioned position identified by history,
  # timeline, and target version.
  #
  # Clean-room reconstruction of `deltadb::history_records` (fields
  # `history_id`, `timeline_id`, `target_version`).
  struct HistoryRecord
    getter history_id : HistoryId
    getter timeline_id : TimelineId
    getter target_version : HistoryVersion

    def initialize(@history_id : HistoryId, @timeline_id : TimelineId, @target_version : HistoryVersion)
    end
  end

  # A checkpoint: the materialized state of a history at some version.
  #
  # Clean-room reconstruction of `deltadb::history_checkpoint::Checkpoint`
  # (fields `registers`, `maps`, `buffers`, `worktrees`, `text_only_object`,
  # `dag`, `snapshots` recovered from the deserializer).
  struct Checkpoint
    getter version : HistoryVersion
    getter registers : Array(AnyRegister(String))
    getter maps : Array(Map)
    getter buffers : Array(Buffer)
    getter worktrees : Array(String)
    getter text_only_object : String?

    def initialize(
      @version : HistoryVersion,
      @registers : Array(AnyRegister(String)) = [] of AnyRegister(String),
      @maps : Array(Map) = [] of Map,
      @buffers : Array(Buffer) = [] of Buffer,
      @worktrees : Array(String) = [] of String,
      @text_only_object : String? = nil,
    )
    end
  end

  # Resolves the merge base of two history versions.
  #
  # Clean-room reconstruction of `deltadb::merge_base_resolver::MergeBaseResolver`
  # and its `LocalBaseResolution`. The upstream computes the greatest common
  # ancestor over the history DAG; here it returns the shared version directly.
  module MergeBaseResolver
    # Returns the common base version when `a` and `b` share one, else nil.
    def self.merge_base(a : HistoryVersion, b : HistoryVersion) : HistoryVersion?
      a == b ? a : nil
    end
  end
end
