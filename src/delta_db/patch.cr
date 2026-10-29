# src/delta_db/patch.cr
module DeltaDB
  struct Patch(T)
    getter edits : Array(Edit(T))

    def initialize(@edits : Array(Edit(T)) = [] of Edit(T))
    end

    def self.empty : Patch(T)
      Patch(T).new
    end

    def empty? : Bool
      @edits.empty?
    end

    def clear : Nil
      @edits.clear
    end

    def push(edit : Edit(T)) : Nil
      push_maybe_empty(edit) unless edit.empty?
    end

    def push_maybe_empty(edit : Edit(T)) : Nil
      last = @edits.last?
      if last && last.old.end >= edit.old.begin
        @edits[-1] = Edit(T).new(last.old.begin..edit.old.end, last.new.begin..edit.new.end)
      else
        @edits << edit
      end
    end

    def invert! : Patch(T)
      @edits.map! { |e| Edit(T).new(e.new, e.old) }
      self
    end

    def old_to_new(old : T) : T
      ix = binary_search_edit(old)
      if ix < 0 || ix >= @edits.size
        old
      else
        edit = @edits[ix]
        if old >= edit.old.end
          edit.new.end + (old - edit.old.end)
        else
          edit.new.begin
        end
      end
    end

    def edit_for_old_position(old : T) : Edit(T)
      ix = binary_search_edit(old)
      if ix < 0 || ix >= @edits.size
        Edit(T).new(old..old, old..old)
      else
        edit = @edits[ix]
        if old > edit.old.end
          translated = edit.new.end + (old - edit.old.end)
          Edit(T).new(old..old, translated..translated)
        else
          edit
        end
      end
    end

    def compose(new_edits : Array(Edit(T))) : Patch(T)
      old_edits = @edits.dup
      new_edits = new_edits.dup
      composed = [] of Edit(T)
      old_idx = 0
      new_idx = 0
      old_start = T.zero
      new_start = T.zero

      while true
        old_edit = old_idx < old_edits.size ? old_edits[old_idx] : nil
        new_edit = new_idx < new_edits.size ? new_edits[new_idx] : nil

        if old_edit && (new_edit.nil? || old_edit.new.end < new_edit.not_nil!.old.begin)
          catchup = old_edit.old.begin - old_start
          old_start += catchup
          new_start += catchup
          old_end = old_start + old_edit.old_size
          new_end = new_start + old_edit.new_size
          composed << Edit(T).new(old_start..old_end, new_start..new_end)
          old_start = old_end
          new_start = new_end
          old_idx += 1
          next
        end

        if new_edit && (old_edit.nil? || new_edit.old.end < old_edit.not_nil!.new.begin)
          catchup = new_edit.new.begin - new_start
          old_start += catchup
          new_start += catchup
          old_end = old_start + new_edit.old_size
          new_end = new_start + new_edit.new_size
          composed << Edit(T).new(old_start..old_end, new_start..new_end)
          old_start = old_end
          new_start = new_end
          new_idx += 1
          next
        end

        if old_edit && new_edit
          oe = old_edit.not_nil!
          ne = new_edit.not_nil!
          if oe.new.begin < ne.old.begin
            catchup = oe.old.begin - old_start
            old_start += catchup
            new_start += catchup
            overshoot = ne.old.begin - oe.new.begin
            old_end = Math.min(old_start + overshoot, oe.old.end)
            new_end = new_start + overshoot
            composed << Edit(T).new(old_start..old_end, new_start..new_end)
            old_edits[old_idx] = Edit(T).new(old_end..oe.old.end, (oe.new.begin + overshoot)..oe.new.end)
            old_start = old_end
            new_start = new_end
          else
            catchup = ne.new.begin - new_start
            old_start += catchup
            new_start += catchup
            overshoot = oe.new.begin - ne.old.begin
            old_end = old_start + overshoot
            new_end = Math.min(new_start + overshoot, ne.new.end)
            composed << Edit(T).new(old_start..old_end, new_start..new_end)
            new_edits[new_idx] = Edit(T).new((ne.old.begin + overshoot)..ne.old.end, new_end..ne.new.end)
            old_start = old_end
            new_start = new_end
          end

          oe = old_edits[old_idx]
          ne = new_edits[new_idx]
          if oe.new.end > ne.old.end
            old_end = old_start + Math.min(oe.old_size, ne.old_size)
            new_end = new_start + ne.new_size
            composed << Edit(T).new(old_start..old_end, new_start..new_end)
            old_edits[old_idx] = Edit(T).new(old_end..oe.old.end, ne.old.end..oe.new.end)
            old_start = old_end
            new_start = new_end
            new_idx += 1
          else
            old_end = old_start + oe.old_size
            new_end = new_start + Math.min(oe.new_size, ne.new_size)
            composed << Edit(T).new(old_start..old_end, new_start..new_end)
            new_edits[new_idx] = Edit(T).new(oe.new.end..ne.old.end, new_end..ne.new.end)
            old_start = old_end
            new_start = new_end
            old_idx += 1
          end
        else
          break
        end
      end

      Patch(T).new(composed)
    end

    private def binary_search_edit(old : T) : Int32
      lo = 0
      hi = @edits.size
      while lo < hi
        mid = (lo + hi) // 2
        if @edits[mid].old.begin <= old
          lo = mid + 1
        else
          hi = mid
        end
      end
      lo - 1
    end
  end
end
