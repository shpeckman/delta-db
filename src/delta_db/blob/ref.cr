# src/delta_db/blob/ref.cr
module DeltaDB
  module Blob
    class Ref
      getter digest : String
      getter size : UInt64
      getter available : Bool

      def initialize(@digest : String, @size : UInt64, @available : Bool = true)
      end

      def resolve(store : BlobStore) : Bytes
        raise MissingBlobError.new("blob is unavailable: #{@digest}") unless @available
        store.get(self)
      end
    end
  end
end
