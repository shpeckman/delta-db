# src/delta_db/edit.cr
module DeltaDB
  struct Edit(D)
    getter old : Range(D, D)
    getter new : Range(D, D)

    def initialize(@old : Range(D, D), @new : Range(D, D))
    end

    def empty? : Bool
      @old.begin == @old.end && @new.begin == @new.end
    end

    def old_len : D
      @old.end - @old.begin
    end

    def new_len : D
      @new.end - @new.begin
    end
  end
end
