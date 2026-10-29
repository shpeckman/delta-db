# src/delta_db/fragment_index/splice.cr
module DeltaDB
  class FragmentIndex
    struct Splice
      getter range : Range(UInt32, UInt32)
      getter text : String

      def initialize(@range : Range(UInt32, UInt32), @text : String)
      end
    end
  end
end
