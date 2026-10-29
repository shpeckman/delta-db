# src/delta_db/text/selection.cr
module DeltaDB
  module Text
    struct Selection(T)
      enum Goal
        None
        HorizontalPosition
        HorizontalRange
        WrappedHorizontalPosition
      end

      getter id : Int32
      getter start : T
      getter end : T
      getter reversed : Bool
      getter goal : SelectionGoal

      def initialize(@id : Int32, @start : T, @end : T, @reversed : Bool, @goal : SelectionGoal)
      end

      def self.from_offset(offset : T) : Selection(T)
        Selection(T).new(0, offset, offset, false, SelectionGoal::None)
      end

      def head : T
        @reversed ? @start : @end
      end

      def tail : T
        @reversed ? @end : @start
      end

      def range : Range(T, T)
        @start..@end
      end

      def collapse_to(point : T, goal : SelectionGoal) : Nil
        @start = point
        @end = point
        @goal = goal
        @reversed = false
      end

      def map(&block : T -> U) : Selection(U) forall U
        Selection(U).new(@id, yield(@start), yield(@end), @reversed, @goal)
      end
    end
  end
end
