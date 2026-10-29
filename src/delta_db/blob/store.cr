# src/delta_db/blob/store.cr
require "digest/sha256"

module DeltaDB
  module Blob
    class Store
      def initialize(@blobs : Hash(String, Bytes) = {} of String => Bytes)
      end

      def put(data : Bytes) : BlobRef
        digest = Digest::SHA256.hexdigest(data)
        @blobs[digest] = data.dup
        BlobRef.new(digest, data.size.to_u64)
      end

      def get(ref : BlobRef) : Bytes
        @blobs.fetch(ref.digest) { raise MissingBlobError.new("missing blob: #{ref.digest}") }
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
  end
end
