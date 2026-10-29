# src/delta_db/fragment_index/edit_plan.cr
module DeltaDB
  class FragmentIndex
    struct EditPlan
      getter fragment_id : FragmentId
      getter splices : Array(ContentSplice)

      def initialize(@fragment_id : FragmentId, @splices : Array(ContentSplice) = [] of ContentSplice)
      end
    end
  end
end
