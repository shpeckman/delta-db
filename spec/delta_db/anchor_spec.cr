# spec/delta_db/anchor_spec.cr
require "../spec_helper"

describe DeltaDB::Text::Bias do
  it "inverts" do
    DeltaDB::Text::Bias::Left.invert.should eq DeltaDB::Text::Bias::Right
    DeltaDB::Text::Bias::Right.invert.should eq DeltaDB::Text::Bias::Left
  end
end

describe DeltaDB::Text::Anchor do
  it "builds a timestamped anchor" do
    buffer = DeltaDB::Text::BufferId.new(42u64)
    ts = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(3u16), 7u32)
    anchor = DeltaDB::Text::Anchor.new(ts, 10u32, DeltaDB::Text::Bias::Right, buffer)
    anchor.timestamp.should eq ts
    anchor.offset.should eq 10u32
    anchor.bias.should eq DeltaDB::Text::Bias::Right
    anchor.buffer_id.should eq buffer
  end

  it "reports min/max anchors" do
    buffer = DeltaDB::Text::BufferId.new(1u64)
    DeltaDB::Text::Anchor.min_for_buffer(buffer).min?.should be_true
    DeltaDB::Text::Anchor.max_for_buffer(buffer).max?.should be_true
    DeltaDB::Text::Anchor.min_for_buffer(buffer).max?.should be_false
  end

  it "produces a 20-byte opaque id with the expected layout" do
    buffer = DeltaDB::Text::BufferId.new(0x0102030405060708u64)
    anchor = DeltaDB::Text::Anchor.new(
      DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(0x1122u16), 0x33445566u32),
      0x778899AAu32,
      DeltaDB::Text::Bias::Right,
      buffer,
    )
    id = anchor.opaque_id
    id.size.should eq 20

    expected = IO::Memory.new
    expected.write_bytes(0x0102030405060708u64, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x778899AAu32, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x33445566u32, IO::ByteFormat::LittleEndian)
    expected.write_bytes(0x1122u16, IO::ByteFormat::LittleEndian)
    expected.write_byte(1u8)
    expected.write_byte(0u8)

    id.should eq expected.to_slice
  end
end
