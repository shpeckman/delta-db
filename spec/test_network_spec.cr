# spec/test_network_spec.cr
require "./spec_helper"

describe TestNetwork do
  it "broadcasts and receives messages" do
    net = TestNetwork(String).new(42u64)
    a = DeltaDB::ReplicaId.new(0u16)
    b = DeltaDB::ReplicaId.new(1u16)
    net.add_peer(a)
    net.add_peer(b)

    net.broadcast(a, ["hi", "there"])
    net.has_unreceived?(a).should be_false
    net.has_unreceived?(b).should be_true
    received = [] of String
    until net.idle?
      received.concat(net.receive(b))
    end
    received.should contain "hi"
    received.should contain "there"
  end

  it "drops broadcasts from disconnected peers" do
    net = TestNetwork(String).new
    a = DeltaDB::ReplicaId.new(0u16)
    b = DeltaDB::ReplicaId.new(1u16)
    net.add_peer(a)
    net.add_peer(b)
    net.disconnect_peer(a)
    net.broadcast(a, ["hi"])
    net.has_unreceived?(b).should be_false
  end
end
