# src/delta_db/client_buffer.cr
module DeltaDB
  class ClientBuffer
    getter buffer_id : BufferId
    getter text_buffer : TextBuffer
    getter seal_state : SealState

    def initialize(@buffer_id : BufferId, fragments : Array(Fragment))
      text = fragments.select(&.visible).map(&.text).join
      @text_buffer = TextBuffer.new(ReplicaId::LOCAL, @buffer_id, text)
      @seal_state = SealState.new
    end

    def initialize(@buffer_id : BufferId, replica_id : ReplicaId = ReplicaId::LOCAL, text : String = "")
      @text_buffer = TextBuffer.new(replica_id, @buffer_id, text)
      @seal_state = SealState.new
    end

    def fragments : Array(Fragment)
      @text_buffer.snapshot.fragments
    end

    def snapshot : BufferSnapshot
      @text_buffer.snapshot
    end

    def to_rope : Rope
      @text_buffer.snapshot.visible_text
    end

    def text : String
      @text_buffer.text
    end

    def bytesize : Int32
      @text_buffer.bytesize
    end

    def edit_as_actor(edits : Array({Range(Int32, Int32), String})) : EditOperation
      @seal_state.ensure_mutable!
      @text_buffer.edit(edits)
    end

    def apply_operation(operation : Operation) : Array(Operation)
      @seal_state.ensure_mutable!
      @text_buffer.apply(operation)
    end

    def create_anchor(offset : Int32, bias : Bias) : Anchor
      bias.left? ? @text_buffer.anchor_before(offset) : @text_buffer.anchor_after(offset)
    end

    def resolve_anchor(anchor : Anchor) : Int32?
      @text_buffer.snapshot.offset_for_anchor(anchor)
    end

    def seal : Nil
      @seal_state.seal(@text_buffer.version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end
  end

  alias Buffer = ClientBuffer
end
