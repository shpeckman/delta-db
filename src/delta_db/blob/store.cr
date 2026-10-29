# src/delta_db/blob/store.cr
require "digest/sha256"

module DeltaDB
  module Blob
    class Store
      getter backend : Memory | Disk

      def initialize(blobs : Hash(String, Bytes) = {} of String => Bytes)
        @backend = Memory.new(blobs)
      end

      def initialize(@backend : Memory | Disk)
      end

      def self.open(root : String) : Store
        new(Disk.new(root))
      end

      def put(data : Bytes) : Ref
        digest = Digest::SHA256.hexdigest(data)
        @backend.write(digest, data)
        Ref.new(digest, data.size.to_u64)
      end

      def get(ref : Ref) : Bytes
        read(ref, &.dup)
      end

      def read(ref : Ref, & : Bytes -> T) : T forall T
        @backend.read(ref.digest) { |bytes| yield bytes }
      end

      def contains?(ref : Ref) : Bool
        @backend.contains?(ref.digest)
      end

      def snapshot : Hash(String, Bytes)
        @backend.snapshot
      end

      def restore(blobs : Hash(String, Bytes)) : Nil
        @backend.restore(blobs)
      end
    end
  end
end
