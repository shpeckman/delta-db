# src/delta_db/rope.cr
module DeltaDB
  abstract class RopeNode
    abstract def summary : TextSummary
  end

  class RopeLeaf < RopeNode
    getter chunk : Chunk
    getter summary : TextSummary

    def initialize(@chunk : Chunk)
      @summary = @chunk.text_summary
    end
  end

  class RopeConcat < RopeNode
    getter summary : TextSummary
    getter left : RopeNode
    getter right : RopeNode

    def initialize(@left : RopeNode, @right : RopeNode)
      @summary = @left.summary + @right.summary
    end
  end

  class Rope
    getter root : RopeNode?

    def initialize(@root : RopeNode? = nil)
    end

    def self.empty : Rope
      Rope.new
    end

    def self.build(text : String) : Rope
      Rope.new(Rope.from_chunks(Rope.chunk(text)))
    end

    def self.new(text : String) : Rope
      build(text)
    end

    def summary : TextSummary
      root = @root
      root ? root.summary : TextSummary.zero
    end

    def len : Int32
      summary.len.to_i32
    end

    def chars : UInt64
      summary.chars
    end

    def len_utf16 : UInt64
      summary.len_utf16.value
    end

    def lines : Point
      summary.lines
    end

    def empty? : Bool
      @root.nil?
    end

    def to_s : String
      String.build do |io|
        append_to(io, @root)
      end
    end

    def append(other : Rope) : Rope
      Rope.new(Rope.concat(@root, other.root))
    end

    def +(other : Rope) : Rope
      append(other)
    end

    def slice(range : Range(Int32, Int32)) : Rope
      Rope.new(Rope.slice_node(@root, range.begin, range.end - range.begin))
    end

    def replace(range : Range(Int32, Int32), text : String) : Rope
      left = slice(0...range.begin)
      right = slice(range.end...len)
      (left + Rope.build(text)) + right
    end

    def offset_to_point(offset : Int32) : Point
      Rope.offset_to_point(@root, offset)
    end

    def point_to_offset(point : Point) : Int32
      Rope.point_to_offset(@root, point)
    end

    def offset_to_point_utf16(offset : Int32) : PointUtf16
      Rope.offset_to_point_utf16(@root, offset)
    end

    def point_utf16_to_offset(point : PointUtf16) : Int32
      Rope.point_utf16_to_offset(@root, point)
    end

    private def append_to(io : IO, node : RopeNode?) : Nil
      case node
      when RopeLeaf
        io << node.chunk.text
      when RopeConcat
        append_to(io, node.left)
        append_to(io, node.right)
      else
      end
    end

    def self.chunk(text : String) : Array(Chunk)
      chunks = [] of Chunk
      bytes = text.to_slice
      n = text.bytesize
      i = 0
      while i < n
        finish = i + Chunk::MAX_BASE
        finish = n if finish > n
        while finish > i && finish < n && !Chunk.char_boundary_byte?(bytes[finish])
          finish -= 1
        end
        chunks << Chunk.new(text.byte_slice(i, finish - i))
        i = finish
      end
      chunks
    end

    def self.from_chunks(chunks : Array(Chunk)) : RopeNode?
      return nil if chunks.empty?
      build_balanced(chunks, 0, chunks.size)
    end

    def self.build_balanced(chunks : Array(Chunk), lo : Int32, hi : Int32) : RopeNode
      if hi - lo == 1
        RopeLeaf.new(chunks[lo])
      else
        mid = (lo + hi) // 2
        left = build_balanced(chunks, lo, mid)
        right = build_balanced(chunks, mid, hi)
        RopeConcat.new(left, right)
      end
    end

    def self.concat(a : RopeNode?, b : RopeNode?) : RopeNode?
      return b if a.nil?
      return a if b.nil?
      RopeConcat.new(a, b)
    end

    def self.slice_node(node : RopeNode?, start : Int32, len : Int32) : RopeNode?
      return nil if node.nil? || len <= 0
      case node
      when RopeLeaf
        RopeLeaf.new(node.chunk.slice(start...(start + len)))
      when RopeConcat
        left_len = node.left.summary.len.to_i32
        if start >= left_len
          slice_node(node.right, start - left_len, len)
        elsif start + len <= left_len
          slice_node(node.left, start, len)
        else
          left_part = slice_node(node.left, start, left_len - start)
          right_part = slice_node(node.right, 0, len - (left_len - start))
          concat(left_part, right_part)
        end
      end
    end

    def self.offset_to_point(node : RopeNode?, offset : Int32) : Point
      case node
      when RopeLeaf
        node.chunk.offset_to_point(offset)
      when RopeConcat
        left_len = node.left.summary.len.to_i32
        if offset < left_len
          offset_to_point(node.left, offset)
        else
          node.left.summary.lines + offset_to_point(node.right, offset - left_len)
        end
      else
        Point.zero
      end
    end

    def self.point_to_offset(node : RopeNode?, point : Point) : Int32
      case node
      when RopeLeaf
        node.chunk.point_to_offset(point)
      when RopeConcat
        left_lines = node.left.summary.lines
        if point < left_lines
          point_to_offset(node.left, point)
        else
          node.left.summary.len.to_i32 + point_to_offset(node.right, point - left_lines)
        end
      else
        0
      end
    end

    def self.offset_to_point_utf16(node : RopeNode?, offset : Int32) : PointUtf16
      case node
      when RopeLeaf
        node.chunk.offset_to_point_utf16(offset)
      when RopeConcat
        left_len = node.left.summary.len.to_i32
        if offset < left_len
          offset_to_point_utf16(node.left, offset)
        else
          node.left.summary.lines_utf16 + offset_to_point_utf16(node.right, offset - left_len)
        end
      else
        PointUtf16.zero
      end
    end

    def self.point_utf16_to_offset(node : RopeNode?, point : PointUtf16) : Int32
      case node
      when RopeLeaf
        node.chunk.point_utf16_to_offset(point)
      when RopeConcat
        left_lines_utf16 = node.left.summary.lines_utf16
        if point < left_lines_utf16
          point_utf16_to_offset(node.left, point)
        else
          node.left.summary.len.to_i32 + point_utf16_to_offset(node.right, point - left_lines_utf16)
        end
      else
        0
      end
    end
  end
end
