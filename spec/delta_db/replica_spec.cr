# spec/delta_db/replica_spec.cr
require "../spec_helper"

describe DeltaDB::Replica do
  it "holds a value and ticks a Lamport clock" do
    map = DeltaDB::Map.new
    replica = DeltaDB::Replica(DeltaDB::Map).new(map)
    first = replica.tick
    first.value.should eq 1u32
    replica.tick.value.should eq 2u32
    replica.value.should eq map
  end
end
