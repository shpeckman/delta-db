# spec/delta_db/diff_spec.cr
require "../spec_helper"

private def apply_ops(a : Array(Int32), b : Array(Int32), ops : Array(DeltaDB::Text::Diff::Op)) : Array(Int32)
  result = [] of Int32
  ai = 0
  bi = 0
  ops.each do |op|
    case op
    in DeltaDB::Text::Diff::Op::Equal
      result << a[ai]
      ai += 1
      bi += 1
    in DeltaDB::Text::Diff::Op::Delete
      ai += 1
    in DeltaDB::Text::Diff::Op::Insert
      result << b[bi]
      bi += 1
    end
  end
  result
end

describe DeltaDB::Text::Diff do
  it "produces a valid edit script reconstructing the target" do
    pairs = [
      {"", ""},
      {"abc", "abc"},
      {"abc", "abd"},
      {"abc", ""},
      {"", "xyz"},
      {"kitten", "sitting"},
      {"hello world", "hello there world"},
      {"abc\ndef", "abc\nghi\ndef"},
    ]
    pairs.each do |(a, b)|
      ac = a.chars.map(&.ord)
      bc = b.chars.map(&.ord)
      ops = DeltaDB::Text::Diff.diff(ac, bc)
      apply_ops(ac, bc, ops).should eq bc
    end
  end

  it "counts equal elements as the LCS" do
    ops = DeltaDB::Text::Diff.chars("kitten", "sitting")
    ops.count(DeltaDB::Text::Diff::Op::Equal).should eq 4
  end

  it "is a no-op (all equal) for identical input" do
    ops = DeltaDB::Text::Diff.chars("same", "same")
    ops.should eq [DeltaDB::Text::Diff::Op::Equal] * 4
  end
end
