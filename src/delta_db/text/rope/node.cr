# src/delta_db/text/rope/node.cr
module DeltaDB
  module Text
    class Rope
      abstract class Node
        abstract def summary : TextSummary
      end

      class Leaf < RopeNode
        getter chunk : Chunk
        getter summary : TextSummary

        def initialize(@chunk : Chunk)
          @summary = @chunk.text_summary
        end
      end

      class Concat < RopeNode
        getter summary : TextSummary
        getter left : RopeNode
        getter right : RopeNode

        def initialize(@left : RopeNode, @right : RopeNode)
          @summary = @left.summary + @right.summary
        end
      end
    end
  end
end
