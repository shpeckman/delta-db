require "../spec_helper"

describe DeltaDB::Bias do
  it "inverts" do
    DeltaDB::Bias::Left.invert.should eq DeltaDB::Bias::Right
    DeltaDB::Bias::Right.invert.should eq DeltaDB::Bias::Left
  end
end

describe DeltaDB::Anchor do
  it "builds a timestamped anchor" do
    buffer = DeltaDB::BufferId.new(42u64)
    ts = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(3u16), 7u32)
    anchor = DeltaDB::Anchor.new(ts, 10u32, DeltaDB::Bias::Right, buffer)
    anchor.timestamp.should eq ts
    anchor.offset.should eq 10u32
    anchor.bias.should eq DeltaDB::Bias::Right
    anchor.buffer_id.should eq buffer
  end

  it "reports min/max anchors" do
    buffer = DeltaDB::BufferId.new(1u64)
    DeltaDB::Anchor.min_for_buffer(buffer).min?.should be_true
    DeltaDB::Anchor.max_for_buffer(buffer).max?.should be_true
    DeltaDB::Anchor.min_for_buffer(buffer).max?.should be_false
  end

  it "produces a 20-byte opaque id with the expected layout" do
    buffer = DeltaDB::BufferId.new(0x0102030405060708u64)
    anchor = DeltaDB::Anchor.new(
      DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0x1122u16), 0x33445566u32),
      0x778899AAu32,
      DeltaDB::Bias::Right,
      buffer,
    )
    id = anchor.opaque_id
    id.size.should eq 20

    expected = IO::Memory.new
    expected.write_bytes(0x0102030405060708u64, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x778899AAu32, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x33445566u32, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x1122u16, IO::ByteFormat::LittleEndian)
    expected.write_byte(1u8) # bias = Right
    expected.write_byte(0u8)

    id.should eq expected.to_slice
  end
end
