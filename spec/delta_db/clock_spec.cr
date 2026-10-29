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
      l.to_u64.should eq (0x12345678u64 << 32) | 3u64
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
    a.to_s.size.should eq 36
  end

  it "orders and compares ids" do
    a = DeltaDB::LocalRepositoryId.random
    b = DeltaDB::LocalRepositoryId.random
    (a == b).should be_false
    (a != b).should be_true
  end

  it "stores sorted unique batch ids and unions versions" do
    first_uuid = UUID.new("00000000-0000-0000-0000-000000000001")
    second_uuid = UUID.new("00000000-0000-0000-0000-000000000002")
    first = DeltaDB::DeltaBatchId.new(first_uuid, 1u64)
    second = DeltaDB::DeltaBatchId.new(second_uuid, 9u64)
    version = DeltaDB::HistoryVersion.from_ids([second, first, second])

    version.ids.should eq [first, second]
    version.size.should eq 2
    version.contains?(first).should be_true
    version.empty?.should be_false
    version.union(DeltaDB::HistoryVersion.from_id(second)).should eq version

    third = DeltaDB::DeltaBatchId.new(first_uuid, 3u64)
    version.observe(third)
    version.ids.should eq [first, third, second]
  end

  it "round-trips the persisted version text format" do
    first_uuid = UUID.new("00000000-0000-0000-0000-000000000001")
    second_uuid = UUID.new("00000000-0000-0000-0000-000000000002")
    first = DeltaDB::DeltaBatchId.new(first_uuid, 1u64)
    second = DeltaDB::DeltaBatchId.new(second_uuid, 9u64)
    version = DeltaDB::HistoryVersion.from_ids([first, second])
    actors_by_uuid = {first_uuid => 0i64, second_uuid => 2i64}
    actors_by_ordinal = {0i64 => DeltaDB::TimelineId.new(first_uuid), 2i64 => DeltaDB::TimelineId.new(second_uuid)}

    text = version.encode_version_text(actors_by_uuid)
    text.should eq "0:1,2:9"
    DeltaDB::HistoryVersion.decode_version_text(text, actors_by_ordinal).should eq version
    DeltaDB::HistoryVersion.decode_version_text("", actors_by_ordinal).empty?.should be_true
  end

  it "rejects malformed version text and unknown actors" do
    actors = {0i64 => DeltaDB::TimelineId.new(UUID.new("00000000-0000-0000-0000-000000000001"))}

    expect_raises(ArgumentError) { DeltaDB::HistoryVersion.decode_version_text("not-a-version", actors) }
    expect_raises(ArgumentError) { DeltaDB::HistoryVersion.decode_version_text("1:2", actors) }
  end

  it "parses timeline ids with reset generations" do
    uuid = UUID.new("00000000-0000-0000-0000-000000000001")
    timeline = DeltaDB::TimelineId.parse("#{uuid}.7")

    timeline.uuid.should eq uuid
    timeline.generation.should eq 7u32
    DeltaDB::TimelineId.parse(uuid.to_s).generation.should eq 0u32
  end
end
