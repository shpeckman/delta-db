# src/delta_db/checkpoint.cr
require "base64"
require "json"

module DeltaDB
  struct CheckpointBatchIdDocument
    include JSON::Serializable

    getter uuid : String
    getter ordinal : UInt64

    def initialize(@uuid : String, @ordinal : UInt64)
    end
  end

  struct CheckpointTimelineIdDocument
    include JSON::Serializable

    getter uuid : String
    getter generation : UInt32

    def initialize(@uuid : String, @generation : UInt32)
    end
  end

  struct CheckpointDeltaDocument
    include JSON::Serializable

    getter history_uuid : String
    getter timeline : CheckpointTimelineIdDocument
    getter actor_uuid : String
    getter replica_id : UInt16
    getter timestamp : UInt32
    getter value_base64 : String

    def initialize(@history_uuid : String, @timeline : CheckpointTimelineIdDocument, @actor_uuid : String, @replica_id : UInt16, @timestamp : UInt32, @value_base64 : String)
    end
  end

  struct CheckpointBatchDocument
    include JSON::Serializable

    getter id : CheckpointBatchIdDocument
    getter timeline : CheckpointTimelineIdDocument
    getter actor_uuid : String
    getter parents : Array(CheckpointBatchIdDocument)
    getter epoch : UInt64
    getter deltas : Array(CheckpointDeltaDocument)

    def initialize(@id : CheckpointBatchIdDocument, @timeline : CheckpointTimelineIdDocument, @actor_uuid : String, @parents : Array(CheckpointBatchIdDocument), @epoch : UInt64, @deltas : Array(CheckpointDeltaDocument))
    end
  end

  struct CheckpointTimelineDocument
    include JSON::Serializable

    getter id : CheckpointTimelineIdDocument
    getter head : Array(CheckpointBatchIdDocument)
    getter origin : Array(CheckpointBatchIdDocument)
    getter parent : CheckpointTimelineIdDocument?
    getter reset_generation : UInt32

    def initialize(@id : CheckpointTimelineIdDocument, @head : Array(CheckpointBatchIdDocument), @origin : Array(CheckpointBatchIdDocument), @parent : CheckpointTimelineIdDocument?, @reset_generation : UInt32)
    end
  end

  struct CheckpointEpochDocument
    include JSON::Serializable

    getter epoch : UInt64
    getter start_version : Array(CheckpointBatchIdDocument)

    def initialize(@epoch : UInt64, @start_version : Array(CheckpointBatchIdDocument))
    end
  end

  struct CheckpointDocument
    include JSON::Serializable

    getter history_uuid : String
    getter max_timestamp : UInt64
    getter epoch_count : UInt64
    getter batches : Array(CheckpointBatchDocument)
    getter timelines : Array(CheckpointTimelineDocument)
    getter epochs : Array(CheckpointEpochDocument)

    def initialize(@history_uuid : String, @max_timestamp : UInt64, @epoch_count : UInt64, @batches : Array(CheckpointBatchDocument), @timelines : Array(CheckpointTimelineDocument), @epochs : Array(CheckpointEpochDocument))
    end
  end

  module CheckpointCodec
    MAGIC = "delta-db-checkpoint-v1\n"

    def self.encode(snapshot : HistoryDagSnapshot) : String
      MAGIC + document(snapshot).to_json
    end

    def self.decode(text : String) : HistoryDagSnapshot
      unless text.starts_with?(MAGIC)
        raise ArgumentError.new("unsupported checkpoint envelope")
      end
      snapshot(CheckpointDocument.from_json(text[MAGIC.size..]))
    end

    def self.document(snapshot : HistoryDagSnapshot) : CheckpointDocument
      CheckpointDocument.new(
        snapshot.history_id.to_s,
        snapshot.max_timestamp,
        snapshot.epoch_count,
        snapshot.batches.sort_by(&.id).map { |batch| batch_document(batch) },
        snapshot.timelines.sort_by(&.id).map { |timeline| timeline_document(timeline) },
        snapshot.epochs.sort_by(&.epoch).map { |epoch| CheckpointEpochDocument.new(epoch.epoch, version_document(epoch.start_version)) },
      )
    end

    def self.snapshot(document : CheckpointDocument) : HistoryDagSnapshot
      HistoryDagSnapshot.new(
        HistoryId.new(UUID.new(document.history_uuid)),
        document.batches.map { |batch| batch_snapshot(batch) },
        document.timelines.map { |timeline| timeline_snapshot(timeline) },
        document.epochs.map { |epoch| HistoryEpoch.new(epoch.epoch, version_snapshot(epoch.start_version)) },
        document.max_timestamp,
        document.epoch_count,
      )
    end

    def self.version_document(version : HistoryVersion) : Array(CheckpointBatchIdDocument)
      version.ids.map { |id| CheckpointBatchIdDocument.new(id.uuid.to_s, id.ordinal) }
    end

    def self.version_snapshot(ids : Array(CheckpointBatchIdDocument)) : HistoryVersion
      HistoryVersion.from_ids(ids.map { |id| DeltaBatchId.new(UUID.new(id.uuid), id.ordinal) })
    end

    def self.timeline_document(id : TimelineId) : CheckpointTimelineIdDocument
      CheckpointTimelineIdDocument.new(id.uuid.to_s, id.generation)
    end

    def self.timeline_snapshot(id : CheckpointTimelineIdDocument) : TimelineId
      TimelineId.new(UUID.new(id.uuid), id.generation)
    end

    private def self.batch_document(batch : HistoryDeltaBatch) : CheckpointBatchDocument
      CheckpointBatchDocument.new(
        CheckpointBatchIdDocument.new(batch.id.uuid.to_s, batch.id.ordinal),
        timeline_document(batch.timeline),
        batch.actor.to_s,
        version_document(batch.parents),
        batch.epoch,
        batch.deltas.map { |delta| delta_document(delta) },
      )
    end

    private def self.batch_snapshot(batch : CheckpointBatchDocument) : HistoryDeltaBatch
      HistoryDeltaBatch.new(
        DeltaBatchId.new(UUID.new(batch.id.uuid), batch.id.ordinal),
        timeline_snapshot(batch.timeline),
        ActorUuid.new(UUID.new(batch.actor_uuid)),
        version_snapshot(batch.parents),
        batch.deltas.map { |delta| delta_snapshot(delta) },
        batch.epoch,
      )
    end

    private def self.timeline_document(timeline : HistoryTimeline) : CheckpointTimelineDocument
      CheckpointTimelineDocument.new(
        timeline_document(timeline.id),
        version_document(timeline.head),
        version_document(timeline.origin),
        timeline.parent.try { |parent| timeline_document(parent) },
        timeline.reset_generation,
      )
    end

    private def self.timeline_snapshot(timeline : CheckpointTimelineDocument) : HistoryTimeline
      HistoryTimeline.new(
        timeline_snapshot(timeline.id),
        version_snapshot(timeline.head),
        version_snapshot(timeline.origin),
        timeline.parent.try { |parent| timeline_snapshot(parent) },
        timeline.reset_generation,
      )
    end

    private def self.delta_document(delta : Delta) : CheckpointDeltaDocument
      CheckpointDeltaDocument.new(
        delta.history.to_s,
        timeline_document(delta.timeline),
        delta.actor.to_s,
        delta.timestamp.replica_id.value,
        delta.timestamp.value,
        Base64.strict_encode(delta.value),
      )
    end

    private def self.delta_snapshot(delta : CheckpointDeltaDocument) : Delta
      Delta.new(
        HistoryId.new(UUID.new(delta.history_uuid)),
        timeline_snapshot(delta.timeline),
        ActorUuid.new(UUID.new(delta.actor_uuid)),
        Lamport.new(ReplicaId.new(delta.replica_id), delta.timestamp),
        Base64.decode(delta.value_base64),
      )
    end
  end

  enum CheckpointPublicationPhase
    Prepared
    Publishing
    Published
    Installed
    Failed
  end

  class CheckpointPublication
    getter id : String
    getter history_id : HistoryId
    getter version : HistoryVersion
    getter encoded : String
    property phase : CheckpointPublicationPhase
    property last_error : String?

    def initialize(@id : String, @history_id : HistoryId, @version : HistoryVersion, @encoded : String, @phase : CheckpointPublicationPhase = CheckpointPublicationPhase::Prepared, @last_error : String? = nil)
    end
  end

  class CheckpointPublisher
    getter publications : Hash(String, CheckpointPublication)

    def initialize
      @publications = {} of String => CheckpointPublication
    end

    def prepare(dag : HistoryDag) : CheckpointPublication
      snapshot = dag.checkpoint
      publication = CheckpointPublication.new(UUID.random.to_s, dag.history_id, dag.timeline_version, CheckpointCodec.encode(snapshot))
      @publications[publication.id] = publication
      publication
    end

    def publish(id : String) : CheckpointPublication
      publication = required(id)
      unless publication.phase.prepared? || publication.phase.publishing?
        raise ArgumentError.new("checkpoint is not ready to publish: #{publication.phase}")
      end
      publication.phase = CheckpointPublicationPhase::Published
      publication
    end

    def install(id : String) : HistoryDag
      publication = required(id)
      unless publication.phase.published?
        raise ArgumentError.new("checkpoint is not published: #{publication.phase}")
      end
      begin
        snapshot = CheckpointCodec.decode(publication.encoded)
        dag = HistoryDag.from_snapshot(snapshot)
        publication.phase = CheckpointPublicationPhase::Installed
        dag
      rescue error
        publication.phase = CheckpointPublicationPhase::Failed
        publication.last_error = error.message
        raise error
      end
    end

    def fail(id : String, message : String) : CheckpointPublication
      publication = required(id)
      publication.phase = CheckpointPublicationPhase::Failed
      publication.last_error = message
      publication
    end

    def get(id : String) : CheckpointPublication?
      @publications[id]?
    end

    def list : Array(CheckpointPublication)
      @publications.values.sort_by(&.id)
    end

    private def required(id : String) : CheckpointPublication
      @publications.fetch(id) { raise ArgumentError.new("missing checkpoint publication: #{id}") }
    end
  end
end
