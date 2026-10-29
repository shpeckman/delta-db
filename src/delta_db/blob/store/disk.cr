# src/delta_db/blob/store/disk.cr
module DeltaDB
  module Blob
    class Store
      class Disk
        TEMP_PREFIX = ".tmp-"

        getter root : String

        def initialize(root : String)
          @root = File.expand_path(root)
          Dir.mkdir_p(@root)
        end

        def path_for(digest : String) : String
          raise ArgumentError.new("invalid blob digest: #{digest}") unless digest.size > 2 && digest.each_char.all?(&.hex?)
          File.join(@root, digest[0, 2], digest[2..])
        end

        def write(digest : String, data : Bytes) : Nil
          path = path_for(digest)
          return if File.exists?(path)
          dir = File.dirname(path)
          Dir.mkdir_p(dir)
          temp = File.join(dir, "#{TEMP_PREFIX}#{Process.pid}-#{Random::Secure.hex(8)}")
          begin
            File.open(temp, "wb") do |file|
              file.write(data)
              file.fsync
            end
            File.rename(temp, path)
          ensure
            File.delete?(temp)
          end
        end

        def read(digest : String, & : Bytes -> T) : T forall T
          path = path_for(digest)
          raise MissingBlobError.new("missing blob: #{digest}") unless File.file?(path)
          File.open(path, "rb") do |file|
            size = file.size.to_i32
            next yield Bytes.empty if size.zero?
            address = LibC.mmap(nil, size, LibC::PROT_READ, LibC::MAP_PRIVATE, file.fd, 0)
            raise RuntimeError.from_errno("mmap #{path}") if address == LibC::MAP_FAILED
            begin
              yield Bytes.new(address.as(UInt8*), size, read_only: true)
            ensure
              LibC.munmap(address, size)
            end
          end
        end

        def contains?(digest : String) : Bool
          File.file?(path_for(digest))
        end

        def digests : Array(String)
          digests = [] of String
          Dir.each_child(@root) do |prefix|
            dir = File.join(@root, prefix)
            next unless prefix.size == 2 && File.directory?(dir)
            Dir.each_child(dir) do |name|
              digests << prefix + name unless name.starts_with?(TEMP_PREFIX)
            end
          end
          digests
        end

        def snapshot : Hash(String, Bytes)
          digests.to_h { |digest| {digest, read(digest, &.dup)} }
        end

        def restore(blobs : Hash(String, Bytes)) : Nil
          digests.each { |digest| File.delete(path_for(digest)) unless blobs.has_key?(digest) }
          blobs.each { |digest, data| write(digest, data) }
        end
      end
    end
  end
end
