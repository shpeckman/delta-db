# src/delta_db/replication/pack.cr
module DeltaDB
  module Replication
    class Pack
      getter id : String
      getter history_id : HistoryId
      getter from_version : HistoryVersion
      getter to_version : HistoryVersion
      getter snapshot : HistoryDagSnapshot
      property sealed : Bool

      def initialize(@id : String, @history_id : HistoryId, @from_version : HistoryVersion, @to_version : HistoryVersion, @snapshot : HistoryDagSnapshot, @sealed : Bool = true)
      end
    end
  end
end
