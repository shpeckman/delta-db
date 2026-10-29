# src/delta_db/history/epoch.cr
module DeltaDB
  module History
    struct Epoch
      getter epoch : UInt64
      getter start_version : Version

      def initialize(@epoch : UInt64, @start_version : Version)
      end
    end
  end
end
