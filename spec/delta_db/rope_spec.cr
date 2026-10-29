# spec/delta_db/rope_spec.cr
require "../spec_helper"

private def char_boundaries(s : String) : Array(Int32)
  boundaries = [0]
  off = 0
  s.each_char do |c|
    off += c.bytesize
    boundaries << off
  end
  boundaries
end

describe DeltaDB::Rope do
  it "round-trips to_s for assorted text" do
    samples = [
      "",
      "hello",
      "hello\nworld\nfoobar",
      "héllo wörld",
      "😀😀😀 mixed",
      "a\tb\tc\n",
      "混合文本 第二行",
      ("hello world\n" * 20),
      "x" * 300,
    ]
    samples.each do |s|
      DeltaDB::Rope.build(s).to_s.should eq s
    end
  end

  it "computes a summary matching the naive oracle" do
    ["", "hello\nworld", "😀😀", ("abc\ndef\n" * 30)].each do |s|
      DeltaDB::Rope.build(s).summary.should eq DeltaDB::TextSummary.from(s)
    end
  end

  it "round-trips offset -> point -> offset at every byte offset" do
    ["hello", "a\nbb\nccc", ("mixed\nlines\n" * 25), "héllo\nwörld\n"].each do |s|
      rope = DeltaDB::Rope.build(s)
      (0..rope.bytesize).each do |offset|
        rope.point_to_offset(rope.offset_to_point(offset)).should eq offset
      end
    end
  end

  it "round-trips offset -> utf16 offset -> offset at char boundaries" do
    ["abc", "héllo", "😀😀😀", ("a😀b\nc\n" * 20)].each do |s|
      rope = DeltaDB::Rope.build(s)
      char_boundaries(s).each do |offset|
        utf16 = rope.offset_to_point_utf16(offset)
        rope.point_utf16_to_offset(utf16).should eq offset
      end
    end
  end

  it "appends two ropes" do
    a = "hello "
    b = "world\nfoobar"
    rope = DeltaDB::Rope.build(a) + DeltaDB::Rope.build(b)
    rope.to_s.should eq a + b
    rope.summary.should eq DeltaDB::TextSummary.from(a + b)
  end

  it "slices sub-ropes" do
    s = "hello\nworld\nfoobar\nbaz"
    rope = DeltaDB::Rope.build(s)
    [{0, 5}, {6, 11}, {0, s.bytesize}, {7, 7}].each do |(lo, hi)|
      rope.slice(lo...hi).to_s.should eq s.byte_slice(lo, hi - lo)
    end
  end

  it "replaces a range" do
    s = "hello world, how are you?"
    rope = DeltaDB::Rope.build(s)
    replaced = rope.replace(6...11, "there")
    replaced.to_s.should eq "hello there, how are you?"
    replaced.summary.should eq DeltaDB::TextSummary.from("hello there, how are you?")
  end

  it "slices across chunk boundaries" do
    s = ("0123456789abcdef" * 20)
    rope = DeltaDB::Rope.build(s)
    rope.slice(120...200).to_s.should eq s.byte_slice(120, 80)
  end
end
