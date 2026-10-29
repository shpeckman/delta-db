# spec/delta_db/map_spec.cr
require "../spec_helper"

describe DeltaDB::Map do
  it "stores and retrieves register values" do
    map = DeltaDB::Map.new
    map.set("name", "delta")
    map.get("name").should eq "delta"
    map.get("missing").should be_nil
  end
end
