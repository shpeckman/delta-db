# spec/delta_db/patch_spec.cr
require "../spec_helper"

describe DeltaDB::Text::Patch do
  it "translates old positions through a patch" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    patch.old_to_new(0).should eq 0
    patch.old_to_new(2).should eq 2
    patch.old_to_new(4).should eq 2
    patch.old_to_new(6).should eq 10
  end

  it "inverts by swapping old/new" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    patch.invert!
    patch.edits.first.old.should eq 2..9
    patch.edits.first.new.should eq 2..5
  end

  it "merges adjacent edits on push" do
    patch = DeltaDB::Text::Patch(Int32).empty
    patch.push(DeltaDB::Text::Edit(Int32).new(0..3, 0..3))
    patch.push(DeltaDB::Text::Edit(Int32).new(3..5, 3..5))
    patch.edits.size.should eq 1
    patch.edits.first.old.should eq 0..5
  end

  it "composes with no new edits as identity" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    composed = patch.compose([] of DeltaDB::Text::Edit(Int32))
    composed.edits.should eq patch.edits
  end

  it "composes disjoint new edits after existing edits" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(0..3, 0..3)])
    composed = patch.compose([DeltaDB::Text::Edit(Int32).new(10..12, 10..15)])
    composed.edits.size.should eq 2
  end
end
