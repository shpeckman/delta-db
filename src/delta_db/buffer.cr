# src/delta_db/buffer.cr
module DeltaDB
  # The goal of a selection (where the cursor "wanted" to be).
  #
  # Port of `crates/text/src/selection.rs` `SelectionGoal`. The numeric payloads
  # (`f64` positions) are dropped in this clean-room port.
  enum SelectionGoal
    None
    HorizontalPosition
    HorizontalRange
    WrappedHorizontalPosition
  end

  # A selection (or cursor) as a possibly-reversed range plus a goal.
  #
  # Port of `crates/text/src/selection.rs` `Selection<T>`.
  struct Selection(T)
    getter id : Int32
    getter start : T
    getter end : T
    getter reversed : Bool
    getter goal : SelectionGoal

    def initialize(@id : Int32, @start : T, @end : T, @reversed : Bool, @goal : SelectionGoal)
    end

    def self.from_offset(offset : T) : Selection(T)
      Selection(T).new(0, offset, offset, false, SelectionGoal::None)
    end

    # The position the selection "stopped" at (the active end).
    def head : T
      @reversed ? @start : @end
    end

    # The position the selection was initiated from.
    def tail : T
      @reversed ? @end : @start
    end

    def range : Range(T, T)
      @start..@end
    end

    def collapse_to(point : T, goal : SelectionGoal) : Nil
      @start = point
      @end = point
      @goal = goal
      @reversed = false
    end

    def map(&block : T -> U) : Selection(U) forall U
      Selection(U).new(@id, yield(@start), yield(@end), @reversed, @goal)
    end
  end

  # A byte offset spanning the full (visible + deleted) text.
  alias FullOffset = UInt32

  # A replacement edit: `old` range replaced by `new` range.
  #
  # Port of `crates/text/src/text.rs` `Edit<D>`.
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

  # A single edit operation: replace `ranges` with `new_text` (1:1).
  #
  # Port of `crates/text/src/text.rs` `EditOperation`.
  struct EditOperation
    getter timestamp : Lamport
    getter version : Global
    getter ranges : Array(Range(FullOffset, FullOffset))
    getter new_text : Array(String)

    def initialize(@timestamp : Lamport, @version : Global, @ranges : Array(Range(FullOffset, FullOffset)), @new_text : Array(String))
    end
  end

  # An undo operation, mapping edited timestamps to undo counts.
  #
  # Port of `crates/text/src/text.rs` `UndoOperation`.
  struct UndoOperation
    getter timestamp : Lamport
    getter version : Global
    getter counts : Hash(Lamport, UInt32)

    def initialize(@timestamp : Lamport, @version : Global, @counts : Hash(Lamport, UInt32))
    end
  end

  # A buffer operation: an edit or an undo.
  alias Operation = EditOperation | UndoOperation

  struct Fragment
    getter id : Locator
    getter timestamp : Lamport
    getter insertion_offset : UInt32
    getter len : UInt32
    property visible : Bool
    property deletions : Array(Lamport)
    property max_undos : Global
    getter text : String

    def initialize(
      @id : Locator,
      @timestamp : Lamport,
      @insertion_offset : UInt32 = 0u32,
      @len : UInt32 = 0u32,
      @visible : Bool = true,
      @deletions : Array(Lamport) = [] of Lamport,
      @max_undos : Global = Global.new,
      @text : String = "",
    )
    end

    def is_visible(undos : UndoMap) : Bool
      !undos.undone?(@timestamp) && @deletions.all? { |deletion| undos.undone?(deletion) }
    end

    def was_visible(version : Global, undos : UndoMap) : Bool
      version.observed?(@timestamp) && !undos.was_undone(@timestamp, version) &&
        @deletions.all? { |deletion| !version.observed?(deletion) || undos.was_undone(deletion, version) }
    end
  end

  struct InsertionFragment
    getter timestamp : Lamport
    getter split_offset : UInt32
    getter fragment_id : Locator

    def initialize(@timestamp : Lamport, @split_offset : UInt32, @fragment_id : Locator)
    end
  end

  class UndoMap
    @entries = Hash(Lamport, Array({Lamport, UInt32})).new

    def insert(undo : UndoOperation) : Nil
      undo.counts.each do |edit_id, count|
        entries = @entries[edit_id] ||= [] of {Lamport, UInt32}
        entries << {undo.timestamp, count} unless entries.any? { |entry| entry[0] == undo.timestamp }
      end
    end

    def undo_count(edit_id : Lamport) : UInt32
      @entries[edit_id]?.try(&.max_of?(&.[1])) || 0u32
    end

    def undone?(edit_id : Lamport) : Bool
      undo_count(edit_id).odd?
    end

    def was_undone(edit_id : Lamport, version : Global) : Bool
      count = 0u32
      @entries[edit_id]?.try do |entries|
        entries.each do |undo_id, undo_count|
          count = Math.max(count, undo_count) if version.observed?(undo_id)
        end
      end
      count.odd?
    end
  end

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
      @fragments.each do |fragment|
        next unless edit_ids.includes?(fragment.timestamp) || fragment.deletions.any? { |deletion| edit_ids.includes?(deletion) }

        fragment.visible = fragment.is_visible(@undo_map)
        fragment.max_undos.observe(undo.timestamp)
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

  class Buffer
    getter snapshot : BufferSnapshot
    getter history : History
    getter lamport_clock : Clock

    def initialize(replica_id : ReplicaId, remote_id : BufferId, base_text : String)
      line_ending = base_text.includes?("\r\n") ? LineEnding::Crlf : LineEnding::Lf
      @snapshot = BufferSnapshot.build(Eol.clean(base_text), remote_id, replica_id, line_ending)
      @history = History.new(@snapshot.visible_text)
      @lamport_clock = Clock.new(Lamport.new(replica_id))
      @lamport_clock.observe(Lamport.new(ReplicaId::LOCAL)) unless base_text.empty?
    end

    def text : String
      @snapshot.text
    end

    def len : Int32
      @snapshot.len
    end

    def version : Global
      @snapshot.version.deep_clone
    end

    def remote_id : BufferId
      @snapshot.remote_id
    end

    def replica_id : ReplicaId
      @snapshot.replica_id
    end

    def edit(edits : Array({Range(Int32, Int32), String})) : EditOperation
      @history.start_transaction(@lamport_clock)
      timestamp = @lamport_clock.tick
      operation = @snapshot.apply_local_edit(edits.map(&.[0]), edits.map(&.[1]), timestamp)
      @history.push(operation)
      @history.push_undo(timestamp)
      @snapshot.version.observe(timestamp)
      @history.end_transaction
      operation
    end

    def apply_ops(ops : Array(Operation)) : Array(Operation)
      ops.each { |op| @history.push(op) }
      applied = @snapshot.apply_ops(ops)
      applied.each { |op| @lamport_clock.observe(op.timestamp) }
      applied
    end

    def apply_op(op : Operation) : Array(Operation)
      apply_ops([op])
    end

    def start_transaction : Lamport?
      @history.start_transaction(@lamport_clock)
    end

    def end_transaction : HistoryEntry?
      @history.end_transaction
    end

    def undo : UndoOperation?
      entry = @history.undo
      entry ? undo_or_redo(entry.transaction) : nil
    end

    def redo : UndoOperation?
      entry = @history.redo
      entry ? undo_or_redo(entry.transaction) : nil
    end

    def undo_or_redo(transaction : Transaction) : UndoOperation
      counts = Hash(Lamport, UInt32).new
      transaction.edit_ids.each do |edit_id|
        counts[edit_id] = @snapshot.undo_map.undo_count(edit_id) + 1u32
      end
      undo_operations(counts)
    end

    def undo_operations(counts : Hash(Lamport, UInt32)) : UndoOperation
      timestamp = @lamport_clock.tick
      operation = UndoOperation.new(timestamp, @snapshot.version.deep_clone, counts)
      @snapshot.apply_op(operation)
      @snapshot.version.observe(timestamp)
      @history.push(operation)
      operation
    end

    def anchor_before(offset : Int32) : Anchor
      @snapshot.anchor_before(offset)
    end

    def anchor_after(offset : Int32) : Anchor
      @snapshot.anchor_after(offset)
    end

    def deferred_ops_len : Int32
      @snapshot.deferred_ops_len
    end

    def check_invariants : Nil
      @snapshot.check_invariants
    end
  end
end
