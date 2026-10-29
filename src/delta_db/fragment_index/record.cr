# src/delta_db/fragment_index/record.cr
module DeltaDB
  class FragmentIndex
    class Record
      getter id : FragmentId
      property text : String
      getter origin : LiteralOrigin

      def initialize(@id : FragmentId, @text : String, @origin : LiteralOrigin)
      end
    end
  end
end
