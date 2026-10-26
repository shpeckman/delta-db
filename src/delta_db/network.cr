module DeltaDB
  # A message-passing network between replicas, used to test CRDT convergence.
  #
  # Port of `crates/text/src/network.rs` `Network<T>`. The upstream uses an RNG
  # to inject duplicate/out-of-order delivery; here delivery is ordered and
  # duplicate-free (a clean-room simplification).
  class Network(T)
    @inboxes = Hash(ReplicaId, Array(T)).new
    @disconnected = Set(ReplicaId).new

    def add_peer(id : ReplicaId) : Nil
      @inboxes[id] = [] of T
    end

    def disconnect_peer(id : ReplicaId) : Nil
      @disconnected << id
      @inboxes[id]?.try(&.clear)
    end

    def reconnect_peer(id : ReplicaId, replicate_from : ReplicaId) : Nil
      @disconnected.delete(id)
      replicate(replicate_from, id)
    end

    def disconnected?(id : ReplicaId) : Bool
      @disconnected.includes?(id)
    end

    def replicate(old_id : ReplicaId, new_id : ReplicaId) : Nil
      @inboxes[new_id] = @inboxes[old_id].dup
    end

    def idle? : Bool
      @inboxes.values.all?(&.empty?)
    end

    def broadcast(sender : ReplicaId, messages : Array(T)) : Nil
      return if @disconnected.includes?(sender)
      @inboxes.each do |replica, inbox|
        next if replica == sender || @disconnected.includes?(replica)
        messages.each { |message| inbox << message }
      end
    end

    def has_unreceived?(receiver : ReplicaId) : Bool
      !(@inboxes[receiver]? || [] of T).empty?
    end

    def receive(receiver : ReplicaId) : Array(T)
      inbox = @inboxes[receiver]? || [] of T
      received = inbox.dup
      inbox.clear
      received
    end
  end
end
