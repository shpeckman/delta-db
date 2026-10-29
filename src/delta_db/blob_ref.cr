# src/delta_db/blob_ref.cr
module DeltaDB
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
end
