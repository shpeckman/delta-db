# spec/delta_db/file_read_diagnostics_spec.cr
require "../spec_helper"

describe DeltaDB::FileReadDiagnostics do
  it "loads a file blob with diagnostics" do
    path = File.tempname("delta-test", ".txt")
    begin
      File.write(path, "hello world")
      result = DeltaDB::FileReadDiagnostics.load_file_blob(path)
      result.should_not be_nil
      bytes, diag = result.not_nil!
      bytes.should eq "hello world".to_slice
      diag.path.should eq path
      diag.bytes.should eq 11u64
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "does not warn for fast reads" do
    diag = DeltaDB::FileReadDiagnostics.new("/tmp/x", 10u64, 1.millisecond)
    DeltaDB::FileReadDiagnostics.warn_if_read_slow(diag)
  end
end
