# src/delta_db/fragment_index/edit_plan.cr
module DeltaDB
  class FragmentIndex
    struct EditPlan
      getter fragment_id : Id
      getter splices : Array(Splice)

      def initialize(@fragment_id : Id, @splices : Array(Splice) = [] of Splice)
      end
    end
  end
end
