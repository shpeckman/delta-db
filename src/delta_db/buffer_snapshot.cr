# src/delta_db/buffer_snapshot.cr
module DeltaDB
  class BufferSnapshot
    getter visible_text : Rope
    getter deleted_text : Rope
    getter fragments : Array(Fragment)
    getter insertions : Array(InsertionFragment)
    getter undo_map : UndoMap
    getter version : Global
    getter remote_id : BufferId
    getter replica_id : ReplicaId
    getter line_ending : LineEnding

    def initialize(
      @visible_text : Rope,
      @deleted_text : Rope,
      @fragments : Array(Fragment),
      @version : Global,
      @remote_id : BufferId,
      @replica_id : ReplicaId,
      @line_ending : LineEnding = LineEnding::Lf,
      @insertions : Array(InsertionFragment) = [] of InsertionFragment,
      @undo_map : UndoMap = UndoMap.new,
    )
      @pending_ops = [] of Operation
    end

    def self.build(text : String, remote_id : BufferId, replica_id : ReplicaId = ReplicaId::LOCAL, line_ending : LineEnding = LineEnding::Lf) : BufferSnapshot
      timestamp = Lamport.new(ReplicaId::LOCAL)
      version = Global.new
      fragments = [] of Fragment
      unless text.empty?
        fragments << Fragment.new(
          Locator.between(Locator.min, Locator.max),
          timestamp,
          0u32,
          text.bytesize.to_u32,
          text: text,
        )
        version.observe(timestamp)
      end
      snapshot = BufferSnapshot.new(Rope.build(text), Rope.empty, fragments, version, remote_id, replica_id, line_ending)
      snapshot.rebuild_insertions
      snapshot
    end

    def text : String
      @visible_text.to_s
    end

    def deleted : String
      @deleted_text.to_s
    end

    def len : Int32
      @visible_text.len
    end

    def empty? : Bool
      @visible_text.empty?
    end

    def apply_local_edit(ranges : Array(Range(Int32, Int32)), new_text : Array(String), timestamp : Lamport) : EditOperation
      unless ranges.size == new_text.size
        raise ArgumentError.new("edit ranges and replacement text must have equal lengths")
      end

      operation_ranges = [] of Range(FullOffset, FullOffset)
      operation_text = [] of String
      (ranges.size - 1).downto(0) do |index|
        range = ranges[index]
        if range.begin < 0 || range.end < range.begin || range.end > len
          raise ArgumentError.new("edit range outside buffer: #{range}")
        end

        full_start = full_offset_for_visible(range.begin).to_u32
        full_end = full_offset_for_visible(range.end).to_u32
        replacement = Eol.clean(new_text[index])
        apply_remote_edit(full_start...full_end, replacement, timestamp, @version)
        operation_ranges.unshift(full_start...full_end)
        operation_text.unshift(replacement)
      end
      rebuild_text
      EditOperation.new(timestamp, @version.deep_clone, operation_ranges, operation_text)
    end

    def apply_ops(ops : Array(Operation)) : Array(Operation)
      @pending_ops.concat(ops)
      applied = [] of Operation
      loop do
        candidate = @pending_ops.find { |op| can_apply_op?(op) }
        break unless candidate

        @pending_ops.delete(candidate)
        next if @version.observed?(candidate.timestamp)

        case candidate
        when EditOperation
          apply_remote_operation(candidate)
        when UndoOperation
          apply_undo_operation(candidate)
        end
        @version.observe(candidate.timestamp)
        applied << candidate
      end
      applied
    end

    def apply_op(op : Operation) : Array(Operation)
      apply_ops([op])
    end

    def edit(ops : Array(EditOperation)) : Array(Operation)
      apply_ops(ops.map { |op| op.as(Operation) })
    end

    def deferred_ops_len : Int32
      @pending_ops.size
    end

    def anchor_before(offset : Int32) : Anchor
      anchor_at_offset(offset, Bias::Left)
    end

    def anchor_after(offset : Int32) : Anchor
      anchor_at_offset(offset, Bias::Right)
    end

    def offset_for_anchor(anchor : Anchor) : Int32?
      return nil if anchor.buffer_id != @remote_id
      return 0 if anchor.min?
      return len if anchor.max?
      return nil unless @version.observed?(anchor.timestamp)

      candidates = @insertions.select { |insertion| insertion.timestamp == anchor.timestamp }
      return nil if candidates.empty?

      insertion = if anchor.bias.left?
                    candidates.select { |candidate| candidate.split_offset < anchor.offset || (anchor.offset == 0 && candidate.split_offset == 0) }.last? || candidates.first
                  else
                    candidates.select { |candidate| candidate.split_offset <= anchor.offset }.last? || candidates.first
                  end
      fragment = @fragments.find { |candidate| candidate.id == insertion.fragment_id }
      return nil unless fragment

      visible_offset = 0
      @fragments.each do |candidate|
        break if candidate.id == fragment.id
        visible_offset += candidate.len.to_i32 if candidate.visible
      end
      return visible_offset unless fragment.visible

      relative = anchor.offset.to_i32 - fragment.insertion_offset.to_i32
      relative = relative.clamp(0, fragment.len.to_i32)
      visible_offset + relative
    end

    def check_invariants : Nil
      previous_id = Locator.min
      @fragments.each do |fragment|
        if fragment.id <= previous_id
          raise "fragment ids are not strictly ordered"
        end
        if fragment.len != fragment.text.bytesize
          raise "fragment length does not match its text"
        end
        previous_id = fragment.id
      end
      rebuild = fragment_text
      if rebuild[0] != text || rebuild[1] != deleted
        raise "fragment text does not match snapshot ropes"
      end
    end

    protected def rebuild_insertions : Nil
      @insertions = @fragments.map do |fragment|
        InsertionFragment.new(fragment.timestamp, fragment.insertion_offset, fragment.id)
      end
      @insertions.sort_by! { |insertion| {insertion.timestamp, insertion.split_offset} }
    end

    private def can_apply_op?(op : Operation) : Bool
      @version.observed_all?(op.version)
    end

    private def apply_remote_operation(op : EditOperation) : Nil
      unless op.ranges.size == op.new_text.size
        raise ArgumentError.new("edit ranges and replacement text must have equal lengths")
      end

      (op.ranges.size - 1).downto(0) do |index|
        range = op.ranges[index]
        apply_remote_edit(range.begin...range.end, Eol.clean(op.new_text[index]), op.timestamp, op.version)
      end
      rebuild_text
    end

    private def apply_undo_operation(undo : UndoOperation) : Nil
      @undo_map.insert(undo)
      edit_ids = undo.counts.keys
      changed = false
      @fragments.each_with_index do |fragment, index|
        next unless edit_ids.includes?(fragment.timestamp) || fragment.deletions.any? { |deletion| edit_ids.includes?(deletion) }

        fragment.visible = fragment.is_visible(@undo_map)
        fragment.max_undos.observe(undo.timestamp)
        @fragments[index] = fragment
        changed = true
      end
      rebuild_text if changed
    end

    private def apply_remote_edit(range : Range(FullOffset, FullOffset), new_text : String, timestamp : Lamport, version : Global) : Nil
      if range.end < range.begin
        raise ArgumentError.new("invalid full-offset edit range")
      end

      updated = [] of Fragment
      inserted = false
      full_offset = 0u32
      @fragments.each do |fragment|
        observed = version.observed?(fragment.timestamp)
        span = observed ? fragment.len : 0u32
        fragment_start = full_offset
        fragment_end = fragment_start + span

        if !inserted && fragment_start >= range.begin && (observed || fragment.timestamp > timestamp)
          insert_fragment(updated, new_text, timestamp, fragment.id)
          inserted = true
        end

        if !observed || fragment_end <= range.begin || fragment_start >= range.end
          updated << fragment
        else
          prefix_length = {range.begin, fragment_start}.max - fragment_start
          intersection_end = {range.end, fragment_end}.min
          intersection_length = intersection_end - {range.begin, fragment_start}.max

          if prefix_length > 0
            updated << fragment_piece(fragment, 0u32, prefix_length, Locator.between(updated.last?.try(&.id) || Locator.min, fragment.id), fragment.visible, fragment.deletions.dup)
          end

          unless inserted
            insert_fragment(updated, new_text, timestamp, fragment.id)
            inserted = true
          end

          if intersection_length > 0
            intersection_start = {range.begin, fragment_start}.max - fragment_start
            deletions = fragment.deletions.dup
            visible = fragment.visible
            if fragment.was_visible(version, @undo_map)
              deletions << timestamp unless deletions.includes?(timestamp)
              visible = false
            end
            updated << fragment_piece(fragment, intersection_start, intersection_length, Locator.between(updated.last?.try(&.id) || Locator.min, fragment.id), visible, deletions)
          end

          suffix_start = intersection_end - fragment_start
          if suffix_start < fragment.len
            updated << fragment_piece(fragment, suffix_start, fragment.len - suffix_start, fragment.id, fragment.visible, fragment.deletions.dup)
          end
        end
        full_offset = fragment_end
      end

      insert_fragment(updated, new_text, timestamp, Locator.max) unless inserted
      @fragments = updated
    end

    private def insert_fragment(fragments : Array(Fragment), text : String, timestamp : Lamport, next_id : Locator) : Nil
      return if text.empty?

      previous_id = fragments.last?.try(&.id) || Locator.min
      id = Locator.between(previous_id, next_id)
      fragments << Fragment.new(id, timestamp, 0u32, text.bytesize.to_u32, text: text)
    end

    private def fragment_piece(fragment : Fragment, start : UInt32, length : UInt32, id : Locator, visible : Bool, deletions : Array(Lamport)) : Fragment
      Fragment.new(
        id,
        fragment.timestamp,
        fragment.insertion_offset + start,
        length,
        visible,
        deletions,
        fragment.max_undos.deep_clone,
        fragment.text.byte_slice(start.to_i32, length.to_i32),
      )
    end

    private def full_offset_for_visible(target : Int32) : Int32
      visible_offset = 0
      full_offset = 0
      @fragments.each do |fragment|
        if fragment.visible
          fragment_end = visible_offset + fragment.len.to_i32
          return full_offset + target - visible_offset if target < fragment_end
          visible_offset = fragment_end
        end
        full_offset += fragment.len.to_i32
      end
      full_offset
    end

    private def anchor_at_offset(offset : Int32, bias : Bias) : Anchor
      if offset < 0 || offset > len
        raise ArgumentError.new("anchor offset outside buffer: #{offset}")
      end
      return Anchor.min_for_buffer(@remote_id) if offset == 0 && bias.left?
      return Anchor.max_for_buffer(@remote_id) if offset == len && bias.right?

      visible_fragments = @fragments.select(&.visible)
      visible_offset = 0
      visible_fragments.each_with_index do |fragment, index|
        fragment_end = visible_offset + fragment.len.to_i32
        if offset < fragment_end || (offset == fragment_end && index == visible_fragments.size - 1)
          relative = offset - visible_offset
          if bias.left? && relative == 0 && index > 0
            previous = visible_fragments[index - 1]
            return Anchor.new(previous.timestamp, previous.insertion_offset + previous.len, bias, @remote_id)
          elsif bias.right? && relative == fragment.len.to_i32 && index < visible_fragments.size - 1
            following = visible_fragments[index + 1]
            return Anchor.new(following.timestamp, following.insertion_offset, bias, @remote_id)
          else
            return Anchor.new(fragment.timestamp, fragment.insertion_offset + relative.to_u32, bias, @remote_id)
          end
        end
        visible_offset = fragment_end
      end
      bias.left? ? Anchor.min_for_buffer(@remote_id) : Anchor.max_for_buffer(@remote_id)
    end

    private def fragment_text : {String, String}
      visible = String.build do |io|
        @fragments.each { |fragment| io << fragment.text if fragment.visible }
      end
      deleted = String.build do |io|
        @fragments.each { |fragment| io << fragment.text unless fragment.visible }
      end
      {visible, deleted}
    end

    private def rebuild_text : Nil
      visible, deleted = fragment_text
      @visible_text = Rope.build(visible)
      @deleted_text = Rope.build(deleted)
      rebuild_insertions
    end
  end
end
