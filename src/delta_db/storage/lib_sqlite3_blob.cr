# src/delta_db/storage/lib_sqlite3_blob.cr
module DeltaDB
  class Storage
    @[Link("sqlite3")]
    lib LibSQLite3Blob
      type Handle = Void*

      fun open = sqlite3_blob_open(db : LibSQLite3::SQLite3, schema : UInt8*, table : UInt8*, column : UInt8*, row : Int64, flags : Int32, blob : Handle*) : Int32
      fun bytes = sqlite3_blob_bytes(blob : Handle) : Int32
      fun read = sqlite3_blob_read(blob : Handle, buffer : Void*, size : Int32, offset : Int32) : Int32
      fun close = sqlite3_blob_close(blob : Handle) : Int32
    end
  end
end
