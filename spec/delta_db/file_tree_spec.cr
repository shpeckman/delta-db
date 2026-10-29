# spec/delta_db/file_tree_spec.cr
require "../spec_helper"

describe DeltaDB::FileMode do
  it "has file/directory/symlink variants" do
    DeltaDB::FileMode::File.should_not eq DeltaDB::FileMode::Directory
    DeltaDB::FileMode::Directory.should_not eq DeltaDB::FileMode::Symlink
  end
end

describe "file tree deltas" do
  it "constructs edit deltas" do
    create = DeltaDB::FileDelta::CreateFile.new("src/a.cr", DeltaDB::FileMode::File, DeltaDB::Text::LineEnding::Lf)
    create.path.should eq "src/a.cr"
    create.mode.should eq DeltaDB::FileMode::File
    create.line_endings.should eq DeltaDB::Text::LineEnding::Lf

    edit = DeltaDB::FileDelta::Edit.new("src/a.cr", "puts 1\n")
    edit.new_text.should eq "puts 1\n"

    rename = DeltaDB::FileDelta::Rename.new("a.cr", "b.cr")
    rename.old_path.should eq "a.cr"
    rename.new_path.should eq "b.cr"
  end
end
