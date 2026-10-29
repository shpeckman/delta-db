# src/delta_db/checkpoint/codec.cr
require "base64"

module DeltaDB
  module Checkpoint
    module Codec
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
  end
end
