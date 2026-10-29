# spec/delta_db/point_spec.cr
require "../spec_helper"

describe DeltaDB::Text::Point do
  it "orders by row then column" do
    (DeltaDB::Text::Point.new(0, 0) < DeltaDB::Text::Point.new(0, 1)).should be_true
    (DeltaDB::Text::Point.new(0, 99) < DeltaDB::Text::Point.new(1, 0)).should be_true
    (DeltaDB::Text::Point.new(2, 3) <=> DeltaDB::Text::Point.new(2, 3)).should eq 0
  end

  it "adds points" do
    (DeltaDB::Text::Point.new(1, 5) + DeltaDB::Text::Point.new(0, 3)).should eq DeltaDB::Text::Point.new(1, 8)
    (DeltaDB::Text::Point.new(1, 5) + DeltaDB::Text::Point.new(2, 9)).should eq DeltaDB::Text::Point.new(3, 9)
  end

  it "subtracts points" do
    (DeltaDB::Text::Point.new(1, 8) - DeltaDB::Text::Point.new(1, 5)).should eq DeltaDB::Text::Point.new(0, 3)
    (DeltaDB::Text::Point.new(3, 9) - DeltaDB::Text::Point.new(1, 5)).should eq DeltaDB::Text::Point.new(2, 9)
  end

  it "saturating_sub floors at zero" do
    (DeltaDB::Text::Point.new(0, 1).saturating_sub(DeltaDB::Text::Point.new(0, 5))).should eq DeltaDB::Text::Point.zero
    (DeltaDB::Text::Point.new(0, 5).saturating_sub(DeltaDB::Text::Point.new(0, 1))).should eq DeltaDB::Text::Point.new(0, 4)
  end
end
