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

  # A fragment of text in a buffer, tracked by insertion order for concurrent
  # edits.
  #
  # Port of `crates/text/src/text.rs` `Fragment`.
  struct Fragment
    getter id : Locator
    getter timestamp : Lamport
    getter insertion_offset : UInt32
    getter len : UInt32
    getter visible : Bool
    getter deletions : Array(Lamport)
    getter max_undos : Global

    def initialize(
      @id : Locator,
      @timestamp : Lamport,
      @insertion_offset : UInt32 = 0u32,
      @len : UInt32 = 0u32,
      @visible : Bool = true,
      @deletions : Array(Lamport) = [] of Lamport,
      @max_undos : Global = Global.new,
    )
    end
  end

  # A pending insertion (text inserted but not yet incorporated).
  struct InsertionFragment
    getter timestamp : Lamport
    getter split_offset : UInt32
    getter fragment_id : Locator

    def initialize(@timestamp : Lamport, @split_offset : UInt32, @fragment_id : Locator)
    end
  end

  # Tracks undo state per edited timestamp. An odd undo count means the edit is
  # currently undone.
  #
  # Clean-room port of `crates/text/src/undo_map.rs` `UndoMap` (the upstream
  # version is a `SumTree` keyed by `(edit_id, undo_id)`; the observable
  # behavior is a per-edit max undo count, so we use a hash).
  class UndoMap
    @counts = Hash(Lamport, UInt32).new

    def insert(undo : UndoOperation) : Nil
      undo.counts.each do |edit_id, count|
        @counts[edit_id] = Math.max(@counts[edit_id]? || 0u32, count)
      end
    end

    def undo_count(edit_id : Lamport) : UInt32
      @counts[edit_id]? || 0u32
    end

    def undone?(edit_id : Lamport) : Bool
      undo_count(edit_id).odd?
    end
  end

  # A snapshot of a buffer's text, tracking visible + deleted text and the
  # ordered fragments that compose it.
  #
  # Clean-room port of `crates/text/src/text.rs` `BufferSnapshot`. The full
  # upstream uses a `SumTree<Fragment>` with a cursor; here fragments are kept in
  # a `Locator`-ordered array.
  class BufferSnapshot
    getter visible_text : Rope
    getter deleted_text : Rope
    getter fragments : Array(Fragment)
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
    )
    end

    # Build a snapshot from plain text (a single visible fragment).
    def self.build(text : String, remote_id : BufferId, replica_id : ReplicaId = ReplicaId::LOCAL) : BufferSnapshot
      rope = Rope.build(text)
      fragment = Fragment.new(
        Locator.between(Locator.min, Locator.max),
        Lamport.new(replica_id),
        0u32,
        text.bytesize.to_u32,
      )
      BufferSnapshot.new(rope, Rope.empty, [fragment], Global.new, remote_id, replica_id)
    end

    def text : String
      @visible_text.to_s
    end

    def len : Int32
      @visible_text.len
    end

    def empty? : Bool
      @visible_text.empty?
    end

    # Apply edit operations, updating visible text and the version vector.
    def edit(ops : Array(EditOperation)) : Nil
      ops.each do |op|
        # Apply ranges right-to-left so earlier ranges' offsets stay valid.
        op.ranges.zip(op.new_text).reverse_each do |range, new_text|
          @visible_text = @visible_text.replace(range.begin.to_i32...range.end.to_i32, new_text)
        end
        @version.observe(op.timestamp)
      end
    end

    # Resolve an anchor to a byte offset (simplified: anchors are offset-based
    # here; the full fragment/timestamp resolution is a later layer).
    def offset_for_anchor(anchor : Anchor) : Int32?
      return nil if anchor.buffer_id != @remote_id
      anchor.offset.to_i32
    end
  end
end
