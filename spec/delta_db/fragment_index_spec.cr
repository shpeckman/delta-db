# spec/delta_db/fragment_index_spec.cr
require "../spec_helper"

describe "fragment index model" do
  it "validates edit ranges" do
    FragmentIndex.valid_ranges?([0u32..2u32, 3u32..5u32]).should be_true
    FragmentIndex.valid_ranges?([0u32..5u32, 3u32..7u32]).should be_false
  end

  it "constructs aliases, splices, and applied edits" do
    id = DeltaDB::FragmentIndex::Id.random
    alias_span = DeltaDB::AliasSpan.new(0u32, 10u32)
    alias_span.end.should eq 10u32

    splice = DeltaDB::FragmentIndex::Splice.new(2u32..5u32, "new")
    splice.text.should eq "new"

    applied = DeltaDB::FragmentIndex::AppliedEdit.new(id, 0u32..3u32, "x")
    applied.fragment_id.should eq id
  end
end

describe "fragment ids" do
  it "generates distinct FragmentIndex::Id and InsertionId" do
    a = DeltaDB::FragmentIndex::Id.random
    b = DeltaDB::FragmentIndex::Id.random
    (a == b).should be_false
    (a < b || a > b).should be_true

    i = DeltaDB::InsertionId.random
    i.to_s.size.should eq 36
  end
end
