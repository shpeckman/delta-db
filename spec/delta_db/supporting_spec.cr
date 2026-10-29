# spec/delta_db/supporting_spec.cr
require "../spec_helper"

describe DeltaDB::GitAttributes do
  it "parses config booleans" do
    DeltaDB::GitAttributes.parse_config_bool("true").should eq true
    DeltaDB::GitAttributes.parse_config_bool("YES").should eq true
    DeltaDB::GitAttributes.parse_config_bool("1").should eq true
    DeltaDB::GitAttributes.parse_config_bool("false").should eq false
    DeltaDB::GitAttributes.parse_config_bool("").should eq false
    DeltaDB::GitAttributes.parse_config_bool("off").should eq false
    DeltaDB::GitAttributes.parse_config_bool("maybe").should be_nil
  end
end

describe DeltaDB::FileMode do
  it "has file/directory/symlink variants" do
    DeltaDB::FileMode::File.should_not eq DeltaDB::FileMode::Directory
    DeltaDB::FileMode::Directory.should_not eq DeltaDB::FileMode::Symlink
  end
end

describe "file tree deltas" do
  it "constructs edit deltas" do
    create = DeltaDB::CreateFileDelta.new("src/a.cr", DeltaDB::FileMode::File, DeltaDB::LineEnding::Lf)
    create.path.should eq "src/a.cr"
    create.mode.should eq DeltaDB::FileMode::File
    create.line_endings.should eq DeltaDB::LineEnding::Lf

    edit = DeltaDB::EditFileDelta.new("src/a.cr", "puts 1\n")
    edit.new_text.should eq "puts 1\n"

    rename = DeltaDB::RenameDelta.new("a.cr", "b.cr")
    rename.old_path.should eq "a.cr"
    rename.new_path.should eq "b.cr"
  end
end

describe "fragment ids" do
  it "generates distinct FragmentId and InsertionId" do
    a = DeltaDB::FragmentId.random
    b = DeltaDB::FragmentId.random
    (a == b).should be_false
    (a < b || a > b).should be_true

    i = DeltaDB::InsertionId.random
    i.to_s.size.should eq 36
  end
end
