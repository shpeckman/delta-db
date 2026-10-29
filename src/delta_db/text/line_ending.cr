# src/delta_db/text/line_ending.cr
module DeltaDB
  module Text
    enum LineEnding
      Lf
      Crlf

      def self.normalize(text : String) : String
        return text unless text.includes?('\r')
        String.build(text.bytesize) do |io|
          i = 0
          n = text.bytesize
          while i < n
            byte = text.byte_at(i)
            if byte == 0x0Du8
              i += 1
              i += 1 if i < n && text.byte_at(i) == 0x0Au8
              io.write_byte(0x0Au8)
            else
              io.write_byte(byte)
              i += 1
            end
          end
        end
      end

      def apply(text : String) : String
        case self
        in .lf?
          LineEnding.normalize(text)
        in .crlf?
          crlf(text)
        end
      end

      private def crlf(text : String) : String
        return text unless text.includes?('\n')
        String.build(text.bytesize) do |io|
          text.each_byte.with_index do |byte, i|
            io.write_byte(0x0Du8) if byte == 0x0Au8 && !(i > 0 && text.byte_at(i - 1) == 0x0Du8)
            io.write_byte(byte)
          end
        end
      end
    end
  end
end
