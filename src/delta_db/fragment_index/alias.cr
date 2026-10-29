# src/delta_db/fragment_index/alias.cr
module DeltaDB
  class FragmentIndex
    struct Alias
      getter fragment_id : Id
      getter span : Range(UInt32, UInt32)

      def initialize(@fragment_id : Id, @span : Range(UInt32, UInt32))
      end
    end
  end
end
