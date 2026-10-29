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
      getter timeline : TimelineIdDocument
      getter actor_uuid : String
      getter replica_id : UInt16
      getter timestamp : UInt32
      getter value_base64 : String

      def initialize(@history_uuid : String, @timeline : TimelineIdDocument, @actor_uuid : String, @replica_id : UInt16, @timestamp : UInt32, @value_base64 : String)
      end
    end

    struct BatchDocument
      include JSON::Serializable

      getter id : BatchIdDocument
      getter timeline : TimelineIdDocument
      getter actor_uuid : String
      getter parents : Array(BatchIdDocument)
      getter epoch : UInt64
      getter deltas : Array(DeltaDocument)

      def initialize(@id : BatchIdDocument, @timeline : TimelineIdDocument, @actor_uuid : String, @parents : Array(BatchIdDocument), @epoch : UInt64, @deltas : Array(DeltaDocument))
      end
    end

    struct TimelineDocument
      include JSON::Serializable

      getter id : TimelineIdDocument
      getter head : Array(BatchIdDocument)
      getter origin : Array(BatchIdDocument)
      getter parent : TimelineIdDocument?
      getter reset_generation : UInt32

      def initialize(@id : TimelineIdDocument, @head : Array(BatchIdDocument), @origin : Array(BatchIdDocument), @parent : TimelineIdDocument?, @reset_generation : UInt32)
      end
    end

    struct EpochDocument
      include JSON::Serializable

      getter epoch : UInt64
      getter start_version : Array(BatchIdDocument)

      def initialize(@epoch : UInt64, @start_version : Array(BatchIdDocument))
      end
    end

    struct Document
      include JSON::Serializable

      getter history_uuid : String
      getter max_timestamp : UInt64
      getter epoch_count : UInt64
      getter batches : Array(BatchDocument)
      getter timelines : Array(TimelineDocument)
      getter epochs : Array(EpochDocument)

      def initialize(@history_uuid : String, @max_timestamp : UInt64, @epoch_count : UInt64, @batches : Array(BatchDocument), @timelines : Array(TimelineDocument), @epochs : Array(EpochDocument))
      end
    end
  end
end
