# src/delta_db/eol.cr
module DeltaDB
  enum LineEnding
    Lf
    Crlf
  end

  module Eol
    CR = 0x0Du8
    LF = 0x0Au8

    def self.clean(text : String) : String
      return text unless text.includes?('\r')
      String.build do |io|
        i = 0
        n = text.bytesize
        while i < n
          b = text.byte_at(i)
          if b == CR
            i += 1
            i += 1 if i < n && text.byte_at(i) == LF
            io.write_byte(LF)
          else
            io.write_byte(b)
            i += 1
          end
        end
      end
    end

    def self.smudge(text : String) : String
      return text unless text.includes?('\n')
      String.build do |io|
        i = 0
        n = text.bytesize
        while i < n
          b = text.byte_at(i)
          if b == LF
            io.write_byte(CR) unless i > 0 && text.byte_at(i - 1) == CR
            io.write_byte(LF)
            i += 1
          else
            io.write_byte(b)
            i += 1
          end
        end
      end
    end
  end
end
