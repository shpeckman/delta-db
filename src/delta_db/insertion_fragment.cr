# src/delta_db/insertion_fragment.cr
module DeltaDB
  struct InsertionFragment
    getter timestamp : Lamport
    getter split_offset : UInt32
    getter fragment_id : Locator

    def initialize(@timestamp : Lamport, @split_offset : UInt32, @fragment_id : Locator)
    end
  end
end
