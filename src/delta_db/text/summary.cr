# src/delta_db/text/summary.cr
module DeltaDB
  module Text
    struct Summary
      getter bytesize : UInt64
      getter chars : UInt64
      getter len_utf16 : OffsetUtf16
      getter lines : Point
      getter first_line_chars : UInt32
      getter last_line_chars : UInt32
      getter last_line_len_utf16 : UInt32
      getter longest_row : UInt32
      getter longest_row_chars : UInt32

      def initialize(
        @bytesize : UInt64 = 0u64,
        @chars : UInt64 = 0u64,
        @len_utf16 : OffsetUtf16 = OffsetUtf16.zero,
        @lines : Point = Point.zero,
        @first_line_chars : UInt32 = 0u32,
        @last_line_chars : UInt32 = 0u32,
        @last_line_len_utf16 : UInt32 = 0u32,
        @longest_row : UInt32 = 0u32,
        @longest_row_chars : UInt32 = 0u32,
      )
      end

      def self.zero : TextSummary
        TextSummary.new
      end

      def self.newline : TextSummary
        TextSummary.new(
          bytesize: 1u64,
          chars: 1u64,
          len_utf16: OffsetUtf16.new(1u64),
          lines: Point.new(1u32, 0u32),
        )
      end

      def self.from(text : String) : TextSummary
        chars = 0u64
        len_utf16 = 0u64
        lines = Point.zero
        first_line_chars = 0u32
        last_line_chars = 0u32
        last_line_len_utf16 = 0u32
        longest_row = 0u32
        longest_row_chars = 0u32

        text.each_char do |c|
          cbytes = c.bytesize
          cutf16 = c.ord > 0xFFFF ? 2 : 1
          chars += 1u64
          len_utf16 += cutf16.to_u64
          if c == '\n'
            lines += Point.new(1u32, 0u32)
            last_line_chars = 0u32
            last_line_len_utf16 = 0u32
          else
            lines = Point.new(lines.row, lines.column + cbytes.to_u32)
            last_line_chars += 1u32
            last_line_len_utf16 += cutf16.to_u32
          end
          first_line_chars = last_line_chars if lines.row == 0
          if last_line_chars > longest_row_chars
            longest_row = lines.row
            longest_row_chars = last_line_chars
          end
        end

        TextSummary.new(
          text.bytesize.to_u64,
          chars,
          OffsetUtf16.new(len_utf16),
          lines,
          first_line_chars,
          last_line_chars,
          last_line_len_utf16,
          longest_row,
          longest_row_chars,
        )
      end

      def lines_utf16 : PointUtf16
        PointUtf16.new(@lines.row, @last_line_len_utf16)
      end

      def add_newline : Nil
        @bytesize += 1u64
        @len_utf16 += OffsetUtf16.new(1u64)
        @last_line_chars = 0u32
        @last_line_len_utf16 = 0u32
        @lines += Point.new(1u32, 0u32)
      end

      def add!(other : TextSummary) : Nil
        joined_chars = @last_line_chars + other.first_line_chars
        if joined_chars > @longest_row_chars
          @longest_row = @lines.row
          @longest_row_chars = joined_chars
        end
        if other.longest_row_chars > @longest_row_chars
          @longest_row = @lines.row + other.longest_row
          @longest_row_chars = other.longest_row_chars
        end

        if @lines.row == 0
          @first_line_chars += other.first_line_chars
        end

        if other.lines.row == 0
          @last_line_chars += other.first_line_chars
          @last_line_len_utf16 += other.last_line_len_utf16
        else
          @last_line_chars = other.last_line_chars
          @last_line_len_utf16 = other.last_line_len_utf16
        end

        @chars += other.chars
        @bytesize += other.bytesize
        @len_utf16 += other.len_utf16
        @lines += other.lines
      end

      def +(other : TextSummary) : TextSummary
        result = self
        result.add!(other)
        result
      end

      def ==(other : TextSummary) : Bool
        @bytesize == other.bytesize &&
          @chars == other.chars &&
          @len_utf16 == other.len_utf16 &&
          @lines == other.lines &&
          @first_line_chars == other.first_line_chars &&
          @last_line_chars == other.last_line_chars &&
          @last_line_len_utf16 == other.last_line_len_utf16 &&
          @longest_row == other.longest_row &&
          @longest_row_chars == other.longest_row_chars
      end
    end
  end
end
