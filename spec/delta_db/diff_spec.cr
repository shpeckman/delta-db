require "../spec_helper"

# Apply an edit script to reconstruct the target from `a` (using `b` to supply
# inserted elements). Returns the reconstructed sequence.
private def apply_ops(a : Array(Int32), b : Array(Int32), ops : Array(DeltaDB::DiffOp)) : Array(Int32)
  result = [] of Int32
  ai = 0
  bi = 0
  ops.each do |op|
    case op
    in DeltaDB::DiffOp::Equal
      result << a[ai]
      ai += 1
      bi += 1
    in DeltaDB::DiffOp::Delete
      ai += 1
    in DeltaDB::DiffOp::Insert
      result << b[bi]
      bi += 1
    end
  end
  result
end

describe DeltaDB::Diff do
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
      ops = DeltaDB::Diff.diff(ac, bc)
      apply_ops(ac, bc, ops).should eq bc
    end
  end

  it "counts equal elements as the LCS" do
    ops = DeltaDB::Diff.chars("kitten", "sitting")
    ops.count(DeltaDB::DiffOp::Equal).should eq 4 # "ittn" is the LCS
  end

  it "is a no-op (all equal) for identical input" do
    ops = DeltaDB::Diff.chars("same", "same")
    ops.should eq [DeltaDB::DiffOp::Equal] * 4
  end
end
