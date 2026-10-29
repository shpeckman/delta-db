# src/delta_db/fragment_index/record.cr
module DeltaDB
  class FragmentIndex
    class Record
      getter id : Id
      property text : String
      getter origin : Origin

      def initialize(@id : Id, @text : String, @origin : Origin)
      end
    end
  end
end
