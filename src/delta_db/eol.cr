module DeltaDB
  # A text file's line-ending style.
  enum LineEnding
    Lf
    Crlf
  end

  # Line-ending normalization, following git's `clean`/`smudge` semantics.
  #
  #   clean  — working-tree -> index/history: CRLF (and stray CR) -> LF
  #   smudge — index/history -> working-tree: LF -> CRLF
  #
  # Port of `deltadb::eol::{clean,smudge}`.
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
            # CRLF or lone CR (old-Mac) both normalize to LF.
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
            # Insert a CR unless already preceded by one.
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
