# src/delta_db/client_operation.cr
module DeltaDB
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
end
