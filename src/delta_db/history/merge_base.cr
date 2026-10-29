# src/delta_db/history/merge_base.cr
module DeltaDB
  module History
    module MergeBase
      def self.resolve(dag : Dag, a : Version, b : Version) : Version?
        base = dag.common_ancestor(a, b)
        base.empty? ? nil : base
      end

      def self.resolve(a : Version, b : Version) : Version?
        a == b ? a : nil
      end
    end
  end
end
