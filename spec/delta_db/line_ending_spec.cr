# spec/delta_db/line_ending_spec.cr
require "../spec_helper"

describe DeltaDB::Text::LineEnding do
  it "normalizes CRLF to LF" do
    DeltaDB::Text::LineEnding.normalize("a\r\nb\r\nc").should eq "a\nb\nc"
  end

  it "normalizes lone CR to LF" do
    DeltaDB::Text::LineEnding.normalize("a\rb").should eq "a\nb"
  end

  it "leaves LF text unchanged when normalizing" do
    DeltaDB::Text::LineEnding.normalize("a\nb\n").should eq "a\nb\n"
  end

  it "applies CRLF to LF text" do
    DeltaDB::Text::LineEnding::Crlf.apply("a\nb\n").should eq "a\r\nb\r\n"
  end

  it "leaves CRLF text unchanged when applying CRLF" do
    DeltaDB::Text::LineEnding::Crlf.apply("a\r\nb\r\n").should eq "a\r\nb\r\n"
  end

  it "applies LF by normalizing" do
    DeltaDB::Text::LineEnding::Lf.apply("a\r\nb").should eq "a\nb"
  end

  it "round-trips LF text through CRLF" do
    ["", "hello\nworld\n", "mixed\nlines"].each do |s|
      DeltaDB::Text::LineEnding.normalize(DeltaDB::Text::LineEnding::Crlf.apply(s)).should eq s
    end
  end
end
