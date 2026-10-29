# src/delta_db/blob/ref.cr
module DeltaDB
  module Blob
    class Ref
      getter digest : String
      getter size : UInt64
      getter available : Bool

      def initialize(@digest : String, @size : UInt64, @available : Bool = true)
      end

      def resolve(store : Store) : Bytes
        ensure_available!
        store.get(self)
      end

      def read(store : Store, & : Bytes -> T) : T forall T
        ensure_available!
        store.read(self) { |bytes| yield bytes }
      end

      private def ensure_available! : Nil
        raise MissingBlobError.new("blob is unavailable: #{@digest}") unless @available
      end
    end
  end
end
