# src/delta_db/text/edit.cr
module DeltaDB
  module Text
    struct Edit(D)
      getter old : Range(D, D)
      getter new : Range(D, D)

      def initialize(@old : Range(D, D), @new : Range(D, D))
      end

      def empty? : Bool
        @old.begin == @old.end && @new.begin == @new.end
      end

      def old_size : D
        @old.end - @old.begin
      end

      def new_size : D
        @new.end - @new.begin
      end
    end
  end
end
