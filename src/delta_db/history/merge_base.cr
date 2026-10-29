# src/delta_db/history/merge_base.cr
module DeltaDB
  module History
    module MergeBase
      def self.merge_base(dag : HistoryDag, a : HistoryVersion, b : HistoryVersion) : HistoryVersion?
        base = dag.common_ancestor(a, b)
        base.empty? ? nil : base
      end

      def self.merge_base(a : HistoryVersion, b : HistoryVersion) : HistoryVersion?
        a == b ? a : nil
      end
    end
  end
end
