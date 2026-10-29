# spec/delta_db/eol_spec.cr
require "../spec_helper"

describe DeltaDB::Eol do
  it "clean normalizes CRLF to LF" do
    DeltaDB::Eol.clean("a\r\nb\r\nc").should eq "a\nb\nc"
  end

  it "clean normalizes lone CR to LF" do
    DeltaDB::Eol.clean("a\rb").should eq "a\nb"
  end

  it "clean leaves LF text unchanged" do
    DeltaDB::Eol.clean("a\nb\n").should eq "a\nb\n"
  end

  it "smudge converts LF to CRLF" do
    DeltaDB::Eol.smudge("a\nb\n").should eq "a\r\nb\r\n"
  end

  it "smudge leaves CRLF text unchanged" do
    DeltaDB::Eol.smudge("a\r\nb\r\n").should eq "a\r\nb\r\n"
  end

  it "clean is a left inverse of smudge on LF text" do
    ["", "hello\nworld\n", "mixed\nlines"].each do |s|
      DeltaDB::Eol.clean(DeltaDB::Eol.smudge(s)).should eq s
    end
  end
end
