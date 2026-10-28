# spec/delta_db/clock_spec.cr
require "../spec_helper"

describe DeltaDB::Clock do
  describe DeltaDB::ReplicaId do
    it "orders and identifies remote replicas" do
      (DeltaDB::ReplicaId::LOCAL < DeltaDB::ReplicaId::REMOTE_SERVER).should be_true
      DeltaDB::ReplicaId::LOCAL.remote?.should be_false
      DeltaDB::ReplicaId::REMOTE_SERVER.remote?.should be_true
      DeltaDB::ReplicaId.new(9u16).remote?.should be_true
      DeltaDB::ReplicaId.new(5u16).remote?.should be_false
    end
  end

  describe DeltaDB::Lamport do
    it "orders by value then replica id" do
      a = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(1u16), 5u32)
      b = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0u16), 5u32)
      (b < a).should be_true
      (DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0u16), 6u32) > a).should be_true
    end

    it "packs into u64" do
      l = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(3u16), 0x12345678u32)
      l.as_u64.should eq (0x12345678u64 << 32) | 3u64
    end
  end

  describe DeltaDB::Clock do
    it "ticks and advances" do
      clock = DeltaDB::Clock.new
      first = clock.tick
      first.value.should eq 1u32
      clock.tick.value.should eq 2u32
    end

    it "observes and advances past a timestamp" do
      clock = DeltaDB::Clock.new
      clock.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(1u16), 10u32))
      clock.tick.value.should eq 11u32
    end
  end

  describe DeltaDB::Global do
    it "observes and reports observed" do
      g = DeltaDB::Global.new
      g.observed?(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 1u32)).should be_false
      g.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 5u32))
      g.observed?(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 5u32)).should be_true
      g.observed?(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 4u32)).should be_true
      g.observed?(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 6u32)).should be_false
    end

    it "joins another global (element-wise max)" do
      a = DeltaDB::Global.new
      b = DeltaDB::Global.new
      a.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0u16), 3u32))
      b.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0u16), 5u32))
      a.join(b)
      a.get(DeltaDB::ReplicaId.new(0u16)).should eq 5u32
    end
  end
end

describe "delta ids" do
  it "generates distinct UUID ids" do
    a = DeltaDB::ActorUuid.random
    b = DeltaDB::ActorUuid.random
    (a == b).should be_false
    a.to_s.size.should eq 36 # canonical uuid string
  end

  it "orders and compares ids" do
    a = DeltaDB::LocalRepositoryId.random
    b = DeltaDB::LocalRepositoryId.random
    (a == b).should be_false
    (a != b).should be_true
  end

  it "HistoryVersion wraps a DeltaBatchId and orders by ordinal" do
    uuid = UUID.random
    a = DeltaDB::HistoryVersion.new(DeltaDB::DeltaBatchId.new(uuid, 0u64))
    b = DeltaDB::HistoryVersion.new(DeltaDB::DeltaBatchId.new(uuid, 1u64))
    (a < b).should be_true
    a.batch_id.ordinal.should eq 0u64
  end
end
