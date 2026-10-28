# src/delta_db/client.cr
require "digest/sha256"

module DeltaDB
  struct AnyRegister(T)
    getter value : T

    def initialize(@value : T)
    end
  end

  class SealState
    getter history_version : HistoryVersion?
    getter global_version : Global?

    def initialize
      @history_version = nil
      @global_version = nil
    end

    def sealed? : Bool
      !@history_version.nil? || !@global_version.nil?
    end

    def seal(version : HistoryVersion) : Nil
      return if @history_version == version
      ensure_mutable!
      @history_version = version
    end

    def seal(version : Global) : Nil
      return if @global_version == version
      ensure_mutable!
      @global_version = version
    end

    def ensure_mutable! : Nil
      raise "object is sealed" if sealed?
    end
  end

  class BlobRef
    getter digest : String
    getter size : UInt64
    getter available : Bool

    def initialize(@digest : String, @size : UInt64, @available : Bool = true)
    end

    def resolve(store : BlobStore) : Bytes
      raise "blob is unavailable: #{@digest}" unless @available
      store.get(self)
    end
  end

  class BlobStore
    def initialize(@blobs : Hash(String, Bytes) = {} of String => Bytes)
    end

    def put(data : Bytes) : BlobRef
      digest = Digest::SHA256.hexdigest(data)
      @blobs[digest] = data.dup
      BlobRef.new(digest, data.size.to_u64)
    end

    def get(ref : BlobRef) : Bytes
      @blobs.fetch(ref.digest) { raise "missing blob: #{ref.digest}" }
    end

    def contains?(ref : BlobRef) : Bool
      @blobs.has_key?(ref.digest)
    end

    def snapshot : Hash(String, Bytes)
      @blobs.transform_values(&.dup)
    end

    def restore(blobs : Hash(String, Bytes)) : Nil
      @blobs = blobs.transform_values(&.dup)
    end
  end

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

    def self.new_file(buffer_id : BufferId, replica_id : ReplicaId = ReplicaId::LOCAL, text : String = "") : ClientBuffer
      ClientBuffer.new(buffer_id, replica_id, text)
    end

    def fragments : Array(Fragment)
      @text_buffer.snapshot.fragments
    end

    def as_snapshot : BufferSnapshot
      @text_buffer.snapshot
    end

    def as_rope : Rope
      @text_buffer.snapshot.visible_text
    end

    def text : String
      @text_buffer.text
    end

    def len : Int32
      @text_buffer.len
    end

    def edit_as_actor(edits : Array({Range(Int32, Int32), String})) : EditOperation
      @seal_state.ensure_mutable!
      @text_buffer.edit(edits)
    end

    def apply_operation(operation : Operation) : Array(Operation)
      @seal_state.ensure_mutable!
      @text_buffer.apply_op(operation)
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

  enum MapEntryKind
    Register
    Blob
    Buffer
    Map
    Worktree
  end

  class MapEntry
    getter kind : MapEntryKind
    getter register_value : String?
    getter blob : BlobRef?
    getter buffer : Buffer?
    getter nested_map : Map?
    getter worktree : Worktree?
    getter version : Global

    def initialize(
      @kind : MapEntryKind,
      @version : Global,
      @register_value : String? = nil,
      @blob : BlobRef? = nil,
      @buffer : Buffer? = nil,
      @nested_map : Map? = nil,
      @worktree : Worktree? = nil,
    )
    end

    def self.register(value : String, version : Global) : MapEntry
      new(MapEntryKind::Register, version, register_value: value)
    end

    def self.blob(value : BlobRef, version : Global) : MapEntry
      new(MapEntryKind::Blob, version, blob: value)
    end

    def self.buffer(value : Buffer, version : Global) : MapEntry
      new(MapEntryKind::Buffer, version, buffer: value)
    end

    def self.map(value : Map, version : Global) : MapEntry
      new(MapEntryKind::Map, version, nested_map: value)
    end

    def self.worktree(value : Worktree, version : Global) : MapEntry
      new(MapEntryKind::Worktree, version, worktree: value)
    end
  end

  class Map
    getter entries : Hash(String, MapEntry)
    getter seal_state : SealState

    def initialize(@entries : Hash(String, MapEntry) = {} of String => MapEntry)
      @seal_state = SealState.new
    end

    def set(key : String, value : String, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.register(value, version)
      @entries[key] = entry
      entry
    end

    def set_blob(key : String, value : BlobRef, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.blob(value, version)
      @entries[key] = entry
      entry
    end

    def set_buffer(key : String, value : Buffer, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.buffer(value, version)
      @entries[key] = entry
      entry
    end

    def set_map(key : String, value : Map, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.map(value, version)
      @entries[key] = entry
      entry
    end

    def set_worktree(key : String, value : Worktree, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.worktree(value, version)
      @entries[key] = entry
      entry
    end

    def get(key : String) : String?
      @entries[key]?.try(&.register_value)
    end

    def entry(key : String) : MapEntry?
      @entries[key]?
    end

    def delete(key : String) : MapEntry?
      @seal_state.ensure_mutable!
      @entries.delete(key)
    end

    def changes(since : Global) : Hash(String, MapEntry)
      @entries.select { |_, entry| entry.version.changed_since?(since) }
    end

    def restore(entries : Hash(String, MapEntry)) : Nil
      @seal_state.ensure_mutable!
      @entries = entries.dup
    end

    def seal(version : HistoryVersion) : Nil
      @seal_state.seal(version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end
  end

  enum ClientOperationKind
    SetRegister
    SetBlob
    SetBuffer
    SetMap
    SetWorktree
    EditBuffer
    EditWorktree
    Delete
    Seal
  end

  class ClientOperation
    getter kind : ClientOperationKind
    getter key : String
    getter text : String
    getter ranges : Array(Range(Int32, Int32))
    getter new_text : Array(String)
    getter blob : BlobRef?
    getter buffer : Buffer?
    getter nested_map : Map?
    getter worktree : Worktree?
    getter file_delta : FileDelta?

    def initialize(
      @kind : ClientOperationKind,
      @key : String = "",
      @text : String = "",
      @ranges : Array(Range(Int32, Int32)) = [] of Range(Int32, Int32),
      @new_text : Array(String) = [] of String,
      @blob : BlobRef? = nil,
      @buffer : Buffer? = nil,
      @nested_map : Map? = nil,
      @worktree : Worktree? = nil,
      @file_delta : FileDelta? = nil,
    )
    end

    def self.register(key : String, value : String) : ClientOperation
      new(ClientOperationKind::SetRegister, key, text: value)
    end

    def self.blob(key : String, value : BlobRef) : ClientOperation
      new(ClientOperationKind::SetBlob, key, blob: value)
    end

    def self.buffer(key : String, value : Buffer) : ClientOperation
      new(ClientOperationKind::SetBuffer, key, buffer: value)
    end

    def self.map(key : String, value : Map) : ClientOperation
      new(ClientOperationKind::SetMap, key, nested_map: value)
    end

    def self.worktree(key : String, value : Worktree) : ClientOperation
      new(ClientOperationKind::SetWorktree, key, worktree: value)
    end

    def self.buffer_edit(key : String, ranges : Array(Range(Int32, Int32)), new_text : Array(String)) : ClientOperation
      new(ClientOperationKind::EditBuffer, key, ranges: ranges, new_text: new_text)
    end

    def self.worktree_edit(key : String, delta : FileDelta) : ClientOperation
      new(ClientOperationKind::EditWorktree, key, file_delta: delta)
    end

    def self.delete(key : String) : ClientOperation
      new(ClientOperationKind::Delete, key)
    end

    def self.seal : ClientOperation
      new(ClientOperationKind::Seal)
    end
  end

  module DeltaApplication
    def self.apply(target : Map, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::SetRegister
        target.set(operation.key, operation.text)
      when ClientOperationKind::SetBlob
        target.set_blob(operation.key, operation.blob.not_nil!)
      when ClientOperationKind::SetBuffer
        target.set_buffer(operation.key, operation.buffer.not_nil!)
      when ClientOperationKind::SetMap
        target.set_map(operation.key, operation.nested_map.not_nil!)
      when ClientOperationKind::SetWorktree
        target.set_worktree(operation.key, operation.worktree.not_nil!)
      when ClientOperationKind::EditBuffer
        buffer = target.entry(operation.key).try(&.buffer) || raise ArgumentError.new("missing buffer: #{operation.key}")
        buffer.edit_as_actor(operation.ranges.zip(operation.new_text).to_a)
      when ClientOperationKind::EditWorktree
        worktree = target.entry(operation.key).try(&.worktree) || raise ArgumentError.new("missing worktree: #{operation.key}")
        worktree.apply(operation.file_delta.not_nil!)
      when ClientOperationKind::Delete
        target.delete(operation.key)
      when ClientOperationKind::Seal
        target.seal(HistoryVersion.from_id(DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)))
      end
    end

    def self.apply(target : ClientBuffer, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::EditBuffer
        target.edit_as_actor(operation.ranges.zip(operation.new_text).to_a)
      when ClientOperationKind::Seal
        target.seal
      else
        raise ArgumentError.new("unsupported buffer operation: #{operation.kind}")
      end
    end

    def self.apply(target : Worktree, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::EditWorktree
        target.apply(operation.file_delta.not_nil!)
      when ClientOperationKind::Seal
        target.seal
      else
        raise ArgumentError.new("unsupported worktree operation: #{operation.kind}")
      end
    end
  end

  class Replica(T)
    getter actor_id : ReplicaId
    getter clock : Clock
    getter value : T
    property history : HistoryDag
    getter seal_state : SealState

    def initialize(@value : T, @actor_id : ReplicaId = ReplicaId::LOCAL, @clock : Clock = Clock.new, history_id : HistoryId = HistoryId.random)
      @history = HistoryDag.new(history_id)
      @seal_state = SealState.new
      @outgoing = [] of HistoryDeltaBatch
    end

    def tick : Lamport
      @clock.tick
    end

    def apply_history_delta(delta : Delta) : HistoryDeltaBatch
      @seal_state.ensure_mutable!
      batch = apply_delta(delta)
      @outgoing << batch
      batch
    end

    def apply_history_delta_batch(batch : HistoryDeltaBatch) : Nil
      @seal_state.ensure_mutable!
      batch.deltas.each { |delta| apply_delta(delta) }
    end

    def outgoing_history_deltas : Array(Delta)
      @outgoing.flat_map(&.deltas)
    end

    def drain_confirmed_outgoing : Array(HistoryDeltaBatch)
      confirmed = @outgoing.dup
      @outgoing.clear
      confirmed
    end

    def seal : Nil
      @seal_state.seal(@history.timeline_version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end

    private def apply_delta(delta : Delta) : HistoryDeltaBatch
      DeltaApplication.apply(@value, delta)
      parents = @history.timelines[delta.timeline]?.try(&.head) || HistoryVersion.new
      id = DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)
      batch = HistoryDeltaBatch.new(id, delta.timeline, delta.actor, parents, [delta])
      @history.insert_on_timeline(batch)
      if delta.operation.try(&.kind) == ClientOperationKind::Seal
        @seal_state.seal(@history.timeline_version)
      end
      batch
    end
  end
end
