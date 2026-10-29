# spec/support/test_network.cr
class TestNetwork(T)
  @inboxes = Hash(DeltaDB::ReplicaId, Array(T)).new
  @disconnected = Set(DeltaDB::ReplicaId).new
  @random : Random

  def initialize
    @random = Random.new
  end

  def initialize(seed : UInt64)
    @random = Random.new(seed)
  end

  def add_peer(id : DeltaDB::ReplicaId) : Nil
    @inboxes[id] = [] of T
  end

  def disconnect_peer(id : DeltaDB::ReplicaId) : Nil
    @disconnected << id
    @inboxes[id]?.try(&.clear)
  end

  def reconnect_peer(id : DeltaDB::ReplicaId, replicate_from : DeltaDB::ReplicaId) : Nil
    @disconnected.delete(id)
    replicate(replicate_from, id)
  end

  def disconnected?(id : DeltaDB::ReplicaId) : Bool
    @disconnected.includes?(id)
  end

  def replicate(old_id : DeltaDB::ReplicaId, new_id : DeltaDB::ReplicaId) : Nil
    @inboxes[new_id] = @inboxes[old_id].dup
  end

  def idle? : Bool
    @inboxes.values.all?(&.empty?)
  end

  def broadcast(sender : DeltaDB::ReplicaId, messages : Array(T)) : Nil
    return if @disconnected.includes?(sender)
    @inboxes.each do |replica, inbox|
      next if replica == sender || @disconnected.includes?(replica)
      messages.each do |message|
        @random.rand(1..3).times do
          inbox.insert(@random.rand(inbox.size + 1), message)
        end
      end
    end
  end

  def has_unreceived?(receiver : DeltaDB::ReplicaId) : Bool
    !(@inboxes[receiver]? || [] of T).empty?
  end

  def receive(receiver : DeltaDB::ReplicaId) : Array(T)
    inbox = @inboxes[receiver]? || [] of T
    inbox.shift(@random.rand(inbox.size + 1))
  end
end
