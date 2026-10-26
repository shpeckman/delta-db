module DeltaDB
  # An edit operation in a diff.
  enum DiffOp
    Equal  # one element present in both sequences
    Insert # one element present only in the target
    Delete # one element present only in the source
  end

  # Sequence diffing.
  #
  # This is an LCS-based edit script (O(n*m)); a clean, correct reimplementation
  # of `deltadb::diff` rather than a port of Zed's `similar`-backed diff. Myers
  # O(ND) is the natural later optimization.
  module Diff
    # A minimal edit script transforming `a` into `b`.
    def self.diff(a : Array(T), b : Array(T)) : Array(DiffOp) forall T
      n = a.size
      m = b.size
      lcs = Array.new(n + 1) { Array(Int32).new(m + 1, 0) }
      (1..n).each do |i|
        (1..m).each do |j|
          lcs[i][j] = a[i - 1] == b[j - 1] ? lcs[i - 1][j - 1] + 1 : Math.max(lcs[i - 1][j], lcs[i][j - 1])
        end
      end

      ops = [] of DiffOp
      i = n
      j = m
      while i > 0 && j > 0
        if a[i - 1] == b[j - 1]
          ops << DiffOp::Equal
          i -= 1
          j -= 1
        elsif lcs[i - 1][j] >= lcs[i][j - 1]
          ops << DiffOp::Delete
          i -= 1
        else
          ops << DiffOp::Insert
          j -= 1
        end
      end
      while i > 0
        ops << DiffOp::Delete
        i -= 1
      end
      while j > 0
        ops << DiffOp::Insert
        j -= 1
      end
      ops.reverse!
    end

    # Character-level diff between two strings.
    def self.chars(a : String, b : String) : Array(DiffOp)
      diff(a.chars.map(&.ord), b.chars.map(&.ord))
    end
  end
end
