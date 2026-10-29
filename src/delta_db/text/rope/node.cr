# src/delta_db/text/rope/node.cr
module DeltaDB
  module Text
    class Rope
      private abstract class Node
        abstract def summary : Summary
      end

      private class Leaf < Node
        getter chunk : Chunk
        getter summary : Summary

        def initialize(@chunk : Chunk)
          @summary = @chunk.text_summary
        end
      end

      private class Concat < Node
        getter summary : Summary
        getter left : Node
        getter right : Node

        def initialize(@left : Node, @right : Node)
          @summary = @left.summary + @right.summary
        end
      end
    end
  end
end
