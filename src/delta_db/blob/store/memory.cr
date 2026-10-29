# src/delta_db/blob/store/memory.cr
module DeltaDB
  module Blob
    class Store
      class Memory
        def initialize(blobs : Hash(String, Bytes) = {} of String => Bytes)
          @blobs = blobs.transform_values(&.dup)
        end

        def write(digest : String, data : Bytes) : Nil
          @blobs[digest] = data.dup unless @blobs.has_key?(digest)
        end

        def read(digest : String, & : Bytes -> T) : T forall T
          bytes = @blobs.fetch(digest) { raise MissingBlobError.new("missing blob: #{digest}") }
          yield Bytes.new(bytes.to_unsafe, bytes.size, read_only: true)
        end

        def contains?(digest : String) : Bool
          @blobs.has_key?(digest)
        end

        def snapshot : Hash(String, Bytes)
          @blobs.transform_values(&.dup)
        end

        def restore(blobs : Hash(String, Bytes)) : Nil
          @blobs = blobs.transform_values(&.dup)
        end
      end
    end
  end
end
