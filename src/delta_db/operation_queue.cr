# src/delta_db/operation_queue.cr
module DeltaDB
  class OperationQueue(T)
    @items = Array(T).new

    def size : Int32
      @items.size
    end

    def empty? : Bool
      @items.empty?
    end

    def insert(ops : Array(T), &timestamp : T -> Lamport) : Nil
      ops.each do |op|
        ts = yield(op)
        @items.reject! { |existing| yield(existing) == ts }
        @items << op
      end
      @items.sort_by! { |op| yield(op) }
    end

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
