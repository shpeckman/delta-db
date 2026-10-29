# src/delta_db/replication/pack_document.cr
require "json"

module DeltaDB
  module Replication
    struct PackDocument
      include JSON::Serializable

      getter id : String
      getter from_version : Array(CheckpointBatchIdDocument)
      getter to_version : Array(CheckpointBatchIdDocument)
      getter checkpoint : CheckpointDocument
      getter sealed : Bool

      def initialize(@id : String, @from_version : Array(CheckpointBatchIdDocument), @to_version : Array(CheckpointBatchIdDocument), @checkpoint : CheckpointDocument, @sealed : Bool)
      end
    end
  end
end
