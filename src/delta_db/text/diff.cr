# src/delta_db/text/diff.cr
module DeltaDB
  module Text
    module Diff
      enum Op
        Equal
        Insert
        Delete
      end

      def self.diff(a : Array(T), b : Array(T)) : Array(Op) forall T
        n = a.size
        m = b.size
        lcs = Array.new(n + 1) { Array(Int32).new(m + 1, 0) }
        (1..n).each do |i|
          (1..m).each do |j|
            lcs[i][j] = a[i - 1] == b[j - 1] ? lcs[i - 1][j - 1] + 1 : Math.max(lcs[i - 1][j], lcs[i][j - 1])
          end
        end

        ops = [] of Op
        i = n
        j = m
        while i > 0 && j > 0
          if a[i - 1] == b[j - 1]
            ops << Op::Equal
            i -= 1
            j -= 1
          elsif lcs[i - 1][j] >= lcs[i][j - 1]
            ops << Op::Delete
            i -= 1
          else
            ops << Op::Insert
            j -= 1
          end
        end
        while i > 0
          ops << Op::Delete
          i -= 1
        end
        while j > 0
          ops << Op::Insert
          j -= 1
        end
        ops.reverse!
      end

      def self.chars(a : String, b : String) : Array(Op)
        diff(a.chars.map(&.ord), b.chars.map(&.ord))
      end
    end
  end
end
