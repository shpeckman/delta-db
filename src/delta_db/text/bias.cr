# src/delta_db/text/bias.cr
module DeltaDB
  module Text
    enum Bias
      Left
      Right

      def invert : Bias
        self == Left ? Right : Left
      end

      def left? : Bool
        self == Left
      end

      def right? : Bool
        self == Right
      end
    end
  end
end
