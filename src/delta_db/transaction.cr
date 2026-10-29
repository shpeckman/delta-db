# src/delta_db/transaction.cr
module DeltaDB
  struct Transaction
    getter id : Lamport
    getter edit_ids : Array(Lamport)
    getter start : Global

    def initialize(@id : Lamport, @edit_ids : Array(Lamport) = [] of Lamport, @start : Global = Global.new)
    end
  end
end
