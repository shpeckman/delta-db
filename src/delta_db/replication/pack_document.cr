# src/delta_db/replication/pack_document.cr
require "json"

module DeltaDB
  module Replication
    struct PackDocument
      include JSON::Serializable

      getter id : String
      getter from_version : Array(Checkpoint::BatchIdDocument)
      getter to_version : Array(Checkpoint::BatchIdDocument)
      getter checkpoint : Checkpoint::Document
      getter sealed : Bool

      def initialize(@id : String, @from_version : Array(Checkpoint::BatchIdDocument), @to_version : Array(Checkpoint::BatchIdDocument), @checkpoint : Checkpoint::Document, @sealed : Bool)
      end
    end
  end
end
