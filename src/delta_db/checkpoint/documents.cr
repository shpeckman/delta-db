# src/delta_db/checkpoint/documents.cr
require "json"

module DeltaDB
  module Checkpoint
    struct BatchIdDocument
      include JSON::Serializable

      getter uuid : String
      getter ordinal : UInt64

      def initialize(@uuid : String, @ordinal : UInt64)
      end
    end

    struct TimelineIdDocument
      include JSON::Serializable

      getter uuid : String
      getter generation : UInt32

      def initialize(@uuid : String, @generation : UInt32)
      end
    end

    struct DeltaDocument
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

    struct BatchDocument
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

    struct TimelineDocument
      include JSON::Serializable

      getter id : CheckpointTimelineIdDocument
      getter head : Array(CheckpointBatchIdDocument)
      getter origin : Array(CheckpointBatchIdDocument)
      getter parent : CheckpointTimelineIdDocument?
      getter reset_generation : UInt32

      def initialize(@id : CheckpointTimelineIdDocument, @head : Array(CheckpointBatchIdDocument), @origin : Array(CheckpointBatchIdDocument), @parent : CheckpointTimelineIdDocument?, @reset_generation : UInt32)
      end
    end

    struct EpochDocument
      include JSON::Serializable

      getter epoch : UInt64
      getter start_version : Array(CheckpointBatchIdDocument)

      def initialize(@epoch : UInt64, @start_version : Array(CheckpointBatchIdDocument))
      end
    end

    struct Document
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
  end
end
