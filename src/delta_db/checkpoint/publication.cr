# src/delta_db/checkpoint/publication.cr
module DeltaDB
  module Checkpoint
    class Publication
      enum Phase
        Prepared
        Publishing
        Published
        Installed
        Failed
      end

      getter id : String
      getter history_id : HistoryId
      getter version : HistoryVersion
      getter encoded : String
      property phase : CheckpointPublicationPhase
      property last_error : String?

      def initialize(@id : String, @history_id : HistoryId, @version : HistoryVersion, @encoded : String, @phase : CheckpointPublicationPhase = CheckpointPublicationPhase::Prepared, @last_error : String? = nil)
      end
    end
  end
end
