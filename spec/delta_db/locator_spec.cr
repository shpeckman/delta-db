# spec/delta_db/locator_spec.cr
require "../spec_helper"

describe DeltaDB::Locator do
  it "orders min before max" do
    (DeltaDB::Locator.min < DeltaDB::Locator.max).should be_true
  end

  it "between produces a locator strictly between its arguments" do
    mid = DeltaDB::Locator.between(DeltaDB::Locator.min, DeltaDB::Locator.max)
    (mid > DeltaDB::Locator.min).should be_true
    (mid < DeltaDB::Locator.max).should be_true
  end

  it "stays at depth 1 for sequential forward appends" do
    prev = DeltaDB::Locator.min
    max = DeltaDB::Locator.max
    1000.times do
      loc = DeltaDB::Locator.between(prev, max)
      loc.size.should eq 1
      prev = loc
    end
  end

  it "stays shallow when typing after a split" do
    initial = DeltaDB::Locator.between(DeltaDB::Locator.min, DeltaDB::Locator.max)
    prefix = DeltaDB::Locator.between(DeltaDB::Locator.min, initial)
    prefix.size.should eq 2

    prev = prefix
    1000.times do
      loc = DeltaDB::Locator.between(prev, initial)
      loc.size.should eq 2
      prev = loc
    end
  end
end
