# src/delta_db/client_operation.cr
module DeltaDB
  class ClientOperation
    enum Kind
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

    getter kind : Kind
    getter key : String
    getter text : String
    getter ranges : Array(Range(Int32, Int32))
    getter new_text : Array(String)
    getter blob : Blob::Ref?
    getter buffer : Buffer?
    getter nested_map : Map?
    getter worktree : Worktree?
    getter file_delta : FileDelta?

    def initialize(
      @kind : Kind,
      @key : String = "",
      @text : String = "",
      @ranges : Array(Range(Int32, Int32)) = [] of Range(Int32, Int32),
      @new_text : Array(String) = [] of String,
      @blob : Blob::Ref? = nil,
      @buffer : Buffer? = nil,
      @nested_map : Map? = nil,
      @worktree : Worktree? = nil,
      @file_delta : FileDelta? = nil,
    )
    end

    def self.register(key : String, value : String) : ClientOperation
      new(Kind::SetRegister, key, text: value)
    end

    def self.blob(key : String, value : Blob::Ref) : ClientOperation
      new(Kind::SetBlob, key, blob: value)
    end

    def self.buffer(key : String, value : Buffer) : ClientOperation
      new(Kind::SetBuffer, key, buffer: value)
    end

    def self.map(key : String, value : Map) : ClientOperation
      new(Kind::SetMap, key, nested_map: value)
    end

    def self.worktree(key : String, value : Worktree) : ClientOperation
      new(Kind::SetWorktree, key, worktree: value)
    end

    def self.buffer_edit(key : String, ranges : Array(Range(Int32, Int32)), new_text : Array(String)) : ClientOperation
      new(Kind::EditBuffer, key, ranges: ranges, new_text: new_text)
    end

    def self.worktree_edit(key : String, delta : FileDelta) : ClientOperation
      new(Kind::EditWorktree, key, file_delta: delta)
    end

    def self.delete(key : String) : ClientOperation
      new(Kind::Delete, key)
    end

    def self.seal : ClientOperation
      new(Kind::Seal)
    end
  end
end
