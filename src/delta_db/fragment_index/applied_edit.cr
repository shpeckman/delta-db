# src/delta_db/fragment_index/applied_edit.cr
module DeltaDB
  class FragmentIndex
    struct AppliedEdit
      getter fragment_id : FragmentId
      getter range : Range(UInt32, UInt32)
      getter text : String

      def initialize(@fragment_id : FragmentId, @range : Range(UInt32, UInt32), @text : String)
      end
    end
  end
end
