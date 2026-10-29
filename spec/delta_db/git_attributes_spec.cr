# spec/delta_db/git_attributes_spec.cr
require "../spec_helper"

describe DeltaDB::Worktree::GitAttributes do
  it "parses config booleans" do
    DeltaDB::Worktree::GitAttributes.parse_config_bool("true").should eq true
    DeltaDB::Worktree::GitAttributes.parse_config_bool("YES").should eq true
    DeltaDB::Worktree::GitAttributes.parse_config_bool("1").should eq true
    DeltaDB::Worktree::GitAttributes.parse_config_bool("false").should eq false
    DeltaDB::Worktree::GitAttributes.parse_config_bool("").should eq false
    DeltaDB::Worktree::GitAttributes.parse_config_bool("off").should eq false
    DeltaDB::Worktree::GitAttributes.parse_config_bool("maybe").should be_nil
  end
end
