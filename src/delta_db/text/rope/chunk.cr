# src/delta_db/text/rope/chunk.cr
module DeltaDB
  module Text
    class Rope
      class Chunk
        MAX_BASE = 128
        MIN_BASE =  64

        getter chars : UInt128
        getter chars_utf16 : UInt128
        getter newlines : UInt128
        getter tabs : UInt128
        getter text : String

        def initialize(text : String)
          raise ArgumentError.new("chunk exceeds #{MAX_BASE} bytes") if text.bytesize > MAX_BASE
          @text = text
          @chars = 0u128
          @chars_utf16 = 0u128
          @newlines = 0u128
          @tabs = 0u128
          text.to_slice.each_with_index do |b, i|
            bit = 1u128 << i
            @chars |= bit if Chunk.char_boundary_byte?(b)
            @newlines |= bit if b == 0x0Au8
            @tabs |= bit if b == 0x09u8
            @chars_utf16 |= bit if b >= 0xF0u8
          end
          @chars_utf16 = (@chars_utf16 << 1) | @chars
        end

        def initialize(@text : String, @chars : UInt128, @chars_utf16 : UInt128, @newlines : UInt128, @tabs : UInt128)
        end

        def self.char_boundary_byte?(b : UInt8) : Bool
          (b & 0xC0u8) != 0x80u8
        end

        def self.saturating_shl_mask(offset : Int32) : UInt128
          offset >= MAX_BASE ? UInt128::MAX : (1u128 << offset) - 1u128
        end

        def self.saturating_shr_mask(offset : Int32) : UInt128
          offset >= MAX_BASE ? UInt128::MAX : ~(UInt128::MAX >> offset)
        end

        def self.nth_set_bit(v : UInt128, n : Int32) : Int32
          count = 0
          (0...MAX_BASE).each do |i|
            if (v & (1u128 << i)) != 0
              count += 1
              return i if count == n
            end
          end
          MAX_BASE
        end

        def bytesize : Int32
          @text.bytesize
        end

        def empty? : Bool
          @text.empty?
        end

        def len_utf16 : OffsetUtf16
          OffsetUtf16.new(@chars_utf16.popcount.to_u64)
        end

        def lines : Point
          row = @newlines.popcount.to_u32
          column = (@newlines.leading_zeros_count.to_i32 - (MAX_BASE - bytesize)).to_u32
          Point.new(row, column)
        end

        def first_line_chars : UInt32
          (@chars & Chunk.saturating_shl_mask(@newlines.trailing_zeros_count.to_i32)).popcount.to_u32
        end

        def last_line_chars : UInt32
          (@chars & Chunk.saturating_shr_mask(@newlines.leading_zeros_count.to_i32)).popcount.to_u32
        end

        def last_line_len_utf16 : UInt32
          (@chars_utf16 & Chunk.saturating_shr_mask(@newlines.leading_zeros_count.to_i32)).popcount.to_u32
        end

        def longest_row : NamedTuple(longest_row: UInt32, longest_row_chars: UInt32)
          chars = @chars
          newlines = @newlines
          row = 0u32
          longest_row = 0u32
          longest_row_chars = 0u32
          while newlines != 0
            newline_ix = newlines.trailing_zeros_count.to_i32
            row_chars = (chars & ((1u128 << newline_ix) - 1u128)).popcount.to_u32
            if row_chars > longest_row_chars
              longest_row = row
              longest_row_chars = row_chars
            end
            newlines >>= newline_ix
            newlines >>= 1
            chars >>= newline_ix
            chars >>= 1
            row += 1u32
          end
          row_chars = chars.popcount.to_u32
          if row_chars > longest_row_chars
            {longest_row: row, longest_row_chars: row_chars}
          else
            {longest_row: longest_row, longest_row_chars: longest_row_chars}
          end
        end

        def text_summary : Summary
          lr = longest_row
          Summary.new(
            bytesize: bytesize.to_u64,
            chars: @chars.popcount.to_u64,
            len_utf16: len_utf16,
            lines: lines,
            first_line_chars: first_line_chars,
            last_line_chars: last_line_chars,
            last_line_len_utf16: last_line_len_utf16,
            longest_row: lr[:longest_row],
            longest_row_chars: lr[:longest_row_chars],
          )
        end

        def is_char_boundary(offset : Int32) : Bool
          return true if offset == @text.bytesize
          return false if offset < 0 || offset > @text.bytesize
          (1u128 << offset) & @chars != 0
        end

        def floor_char_boundary(index : Int32) : Int32
          return @text.bytesize if index >= @text.bytesize
          i = index
          while i > 0
            break if Chunk.char_boundary_byte?(@text.byte_at(i))
            i -= 1
          end
          i
        end

        def ceil_char_boundary(index : Int32) : Int32
          i = index
          while i < @text.bytesize
            break if Chunk.char_boundary_byte?(@text.byte_at(i))
            i += 1
          end
          i
        end

        def offset_to_point(offset : Int32) : Point
          mask = Chunk.saturating_shl_mask(offset)
          row = (@newlines & mask).popcount.to_u32
          newline_ix = MAX_BASE - (@newlines & mask).leading_zeros_count.to_i32
          column = (offset - newline_ix).to_u32
          Point.new(row, column)
        end

        def point_to_offset(point : Point) : Int32
          return bytesize if point.row > lines.row
          range = offset_range_for_row(point.row)
          return range.end if point.column > (range.end - range.begin).to_u32
          range.begin + point.column.to_i32
        end

        def offset_to_offset_utf16(offset : Int32) : OffsetUtf16
          mask = Chunk.saturating_shl_mask(offset)
          OffsetUtf16.new((@chars_utf16 & mask).popcount.to_u64)
        end

        def offset_utf16_to_offset(target : OffsetUtf16) : Int32
          return 0 if target.value == 0
          ix = Chunk.nth_set_bit(@chars_utf16, target.value.to_i32) + 1
          return MAX_BASE if ix == MAX_BASE
          utf8_additional = Math.min((@chars_utf16 >> ix).trailing_zeros_count.to_i32, @text.bytesize - ix)
          ix + utf8_additional
        end

        def offset_to_point_utf16(offset : Int32) : PointUtf16
          mask = Chunk.saturating_shl_mask(offset)
          row = (@newlines & mask).popcount.to_u32
          newline_ix = MAX_BASE - (@newlines & mask).leading_zeros_count.to_i32
          column = if newline_ix == MAX_BASE
                     0u32
                   else
                     ((@chars_utf16 & mask) >> newline_ix).popcount.to_u32
                   end
          PointUtf16.new(row, column)
        end

        def point_to_point_utf16(point : Point) : PointUtf16
          offset_to_point_utf16(point_to_offset(point))
        end

        def point_utf16_to_offset(point : PointUtf16, clip : Bool = true) : Int32
          return bytesize if point.row > lines.row
          range = offset_range_for_row(point.row)
          line = slice(range)
          return range.end if point.column > line.last_line_len_utf16
          offset = range.begin
          if point.column > 0
            offset += line.offset_utf16_to_offset(OffsetUtf16.new(point.column.to_u64))
            unless is_char_boundary(offset)
              offset -= 1
              while !is_char_boundary(offset)
                offset -= 1
              end
            end
          end
          offset
        end

        def offset_range_for_row(row : UInt32) : Range(Int32, Int32)
          row_start = row > 0 ? Chunk.nth_set_bit(@newlines, row.to_i32) + 1 : 0
          row_len = if row_start == MAX_BASE
                      0
                    else
                      Math.min((@newlines >> row_start).trailing_zeros_count.to_i32, bytesize - row_start)
                    end
          row_start...(row_start + row_len)
        end

        def slice(range : Range(Int32, Int32)) : Chunk
          start = range.begin
          finish = range.end
          return Chunk.new("") if start == MAX_BASE
          start = ceil_char_boundary(start) unless is_char_boundary(start)
          unless is_char_boundary(finish)
            finish = finish < start ? start : floor_char_boundary(finish)
          end
          mask = Chunk.saturating_shl_mask(finish)
          Chunk.new(
            @text.byte_slice(start, finish - start),
            (@chars & mask) >> start,
            (@chars_utf16 & mask) >> start,
            (@newlines & mask) >> start,
            (@tabs & mask) >> start,
          )
        end

        def split_at(mid : Int32) : {Chunk, Chunk}
          if mid == MAX_BASE
            return {self, Chunk.new("")}
          end
          mask = (1u128 << mid) - 1u128
          left = Chunk.new(
            @text.byte_slice(0, mid),
            @chars & mask,
            @chars_utf16 & mask,
            @newlines & mask,
            @tabs & mask,
          )
          right = Chunk.new(
            @text.byte_slice(mid),
            @chars >> mid,
            @chars_utf16 >> mid,
            @newlines >> mid,
            @tabs >> mid,
          )
          {left, right}
        end

        def append(other : Chunk) : Nil
          return if other.empty?
          base = @text.bytesize
          @chars |= other.chars << base
          @chars_utf16 |= other.chars_utf16 << base
          @newlines |= other.newlines << base
          @tabs |= other.tabs << base
          @text += other.text
        end

        def prepend(other : Chunk) : Nil
          return if other.empty?
          if @text.empty?
            @text = other.text
            @chars = other.chars
            @chars_utf16 = other.chars_utf16
            @newlines = other.newlines
            @tabs = other.tabs
            return
          end
          shift = other.bytesize
          @chars = other.chars | (@chars << shift)
          @chars_utf16 = other.chars_utf16 | (@chars_utf16 << shift)
          @newlines = other.newlines | (@newlines << shift)
          @tabs = other.tabs | (@tabs << shift)
          @text = other.text + @text
        end

        def push_str(text : String) : Nil
          append(Chunk.new(text))
        end

        def prepend_str(text : String) : Nil
          prepend(Chunk.new(text))
        end

        def to_s(io : IO) : Nil
          io << @text
        end
      end
    end
  end
end
