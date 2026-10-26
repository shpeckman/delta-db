module DeltaDB
  # A queue of operations keyed by their Lamport timestamp, kept sorted and
  # deduplicated.
  #
  # Clean-room port of `crates/text/src/operation_queue.rs` `OperationQueue<T>`
  # (upstream is a `SumTree` keyed by timestamp; here a sorted array).
  class OperationQueue(T)
    @items = Array(T).new

    def size : Int32
      @items.size
    end

    def empty? : Bool
      @items.empty?
    end

    # Insert operations, sorted by timestamp and deduplicated by timestamp.
    def insert(ops : Array(T), &timestamp : T -> Lamport) : Nil
      ops.each do |op|
        ts = yield(op)
        @items.reject! { |existing| yield(existing) == ts }
        @items << op
      end
      @items.sort_by! { |op| yield(op) }
    end

    # Remove and return all queued operations.
    def drain : Array(T)
      ops = @items.dup
      @items.clear
      ops
    end

    def each(&) : Nil
      @items.each { |op| yield op }
    end
  end
end
