# src/delta_db/fragment_index/alias.cr
module DeltaDB
  class FragmentIndex
    struct Alias
      getter fragment_id : FragmentId
      getter span : Range(UInt32, UInt32)

      def initialize(@fragment_id : FragmentId, @span : Range(UInt32, UInt32))
      end
    end
  end
end
