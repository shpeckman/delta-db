# spec/delta_db/chunk_spec.cr
require "../spec_helper"

describe DeltaDB::Chunk do
  it "computes a text summary matching the naive reference" do
    samples = [
      "",
      "hello",
      "hello\nworld",
      "a\nbb\nccc\n",
      "\n\n\n",
      "héllo wörld",
      "😀😀😀",
      "a\tb\tc",
      "混合文本\n第二行",
      "x" * 127,
    ]
    samples.each do |s|
      chunk = DeltaDB::Chunk.new(s)
      chunk.text_summary.should eq DeltaDB::TextSummary.from(s)
    end
  end

  it "reports byte length and utf16 length" do
    DeltaDB::Chunk.new("hello").bytesize.should eq 5
    DeltaDB::Chunk.new("héllo").bytesize.should eq 6
    DeltaDB::Chunk.new("😀").len_utf16.value.should eq 2
    DeltaDB::Chunk.new("abc").len_utf16.value.should eq 3
  end

  it "reports lines (row count and last-line byte column)" do
    DeltaDB::Chunk.new("hello").lines.should eq DeltaDB::Point.new(0, 5)
    DeltaDB::Chunk.new("hello\nworld").lines.should eq DeltaDB::Point.new(1, 5)
    DeltaDB::Chunk.new("a\nbb\n").lines.should eq DeltaDB::Point.new(2, 0)
  end

  it "round-trips offset -> point -> offset at every char boundary" do
    ["hello", "a\nbb\nccc", "héllo\nwörld\n"].each do |s|
      chunk = DeltaDB::Chunk.new(s)
      (0..chunk.bytesize).each do |offset|
        next unless chunk.is_char_boundary(offset)
        point = chunk.offset_to_point(offset)
        chunk.point_to_offset(point).should eq offset
      end
    end
  end

  it "round-trips offset -> utf16 offset -> offset" do
    ["abc", "héllo", "😀😀", "a😀b\nc"].each do |s|
      chunk = DeltaDB::Chunk.new(s)
      (0..chunk.bytesize).each do |offset|
        next unless chunk.is_char_boundary(offset)
        utf16 = chunk.offset_to_offset_utf16(offset)
        chunk.offset_utf16_to_offset(utf16).should eq offset
      end
    end
  end

  it "slices to an equivalent sub-chunk" do
    s = "hello\nworld\nfoobar"
    chunk = DeltaDB::Chunk.new(s)
    sub = chunk.slice(6...11)
    sub.text.should eq "world"
    sub.text_summary.should eq DeltaDB::TextSummary.from("world")
  end

  it "split_at splits into two equivalent chunks" do
    s = "hello world"
    chunk = DeltaDB::Chunk.new(s)
    left, right = chunk.split_at(5)
    left.text.should eq "hello"
    right.text.should eq " world"
    left.text_summary.should eq DeltaDB::TextSummary.from("hello")
    right.text_summary.should eq DeltaDB::TextSummary.from(" world")
  end

  it "appends and prepends while preserving summary" do
    a = DeltaDB::Chunk.new("hello ")
    a.append(DeltaDB::Chunk.new("world"))
    a.text.should eq "hello world"
    a.text_summary.should eq DeltaDB::TextSummary.from("hello world")

    b = DeltaDB::Chunk.new("world")
    b.prepend(DeltaDB::Chunk.new("hello "))
    b.text.should eq "hello world"
    b.text_summary.should eq DeltaDB::TextSummary.from("hello world")
  end

  it "rejects text exceeding MAX_BASE bytes" do
    expect_raises(ArgumentError) do
      DeltaDB::Chunk.new("x" * 129)
    end
  end
end
