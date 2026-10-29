# spec/delta_db/fragment_index_spec.cr
require "../spec_helper"

describe DeltaDB::FragmentIndex do
  it "validates edit ranges" do
    DeltaDB::FragmentIndex.valid_ranges?([0u32..2u32, 3u32..5u32]).should be_true
    DeltaDB::FragmentIndex.valid_ranges?([0u32..5u32, 3u32..7u32]).should be_false
  end

  it "constructs splices and applied edits" do
    id = DeltaDB::FragmentIndex::Id.random
    splice = DeltaDB::FragmentIndex::Splice.new(2u32..5u32, "new")
    splice.text.should eq "new"

    applied = DeltaDB::FragmentIndex::AppliedEdit.new(id, 0u32..3u32, "x")
    applied.fragment_id.should eq id
  end
end

describe DeltaDB::FragmentIndex::Id do
  it "generates distinct ids" do
    a = DeltaDB::FragmentIndex::Id.random
    b = DeltaDB::FragmentIndex::Id.random
    (a == b).should be_false
    (a < b || a > b).should be_true

    a.to_s.size.should eq 36
  end
end
