# src/delta_db/buffer.cr
module DeltaDB
  class Buffer
    getter buffer_id : Text::BufferId
    getter text_buffer : Text::Buffer
    getter seal_state : SealState

    def initialize(@buffer_id : Text::BufferId, fragments : Array(Text::Fragment))
      text = fragments.select(&.visible).map(&.text).join
      @text_buffer = Text::Buffer.new(ReplicaId::LOCAL, @buffer_id, text)
      @seal_state = SealState.new
    end

    def initialize(@buffer_id : Text::BufferId, replica_id : ReplicaId = ReplicaId::LOCAL, text : String = "")
      @text_buffer = Text::Buffer.new(replica_id, @buffer_id, text)
      @seal_state = SealState.new
    end

    def fragments : Array(Text::Fragment)
      @text_buffer.snapshot.fragments
    end

    def snapshot : Text::Snapshot
      @text_buffer.snapshot
    end

    def to_rope : Text::Rope
      @text_buffer.snapshot.visible_text
    end

    def text : String
      @text_buffer.text
    end

    def bytesize : Int32
      @text_buffer.bytesize
    end

    def edit_as_actor(edits : Array({Range(Int32, Int32), String})) : Text::EditOperation
      @seal_state.ensure_mutable!
      @text_buffer.edit(edits)
    end

    def apply_operation(operation : Text::Operation) : Array(Text::Operation)
      @seal_state.ensure_mutable!
      @text_buffer.apply(operation)
    end

    def create_anchor(offset : Int32, bias : Text::Bias) : Text::Anchor
      bias.left? ? @text_buffer.anchor_before(offset) : @text_buffer.anchor_after(offset)
    end

    def resolve_anchor(anchor : Text::Anchor) : Int32?
      @text_buffer.snapshot.offset_for_anchor(anchor)
    end

    def seal : Nil
      @seal_state.seal(@text_buffer.version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end
  end
end
