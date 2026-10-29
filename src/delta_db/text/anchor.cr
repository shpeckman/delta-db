# src/delta_db/text/anchor.cr
module DeltaDB
  module Text
    struct Anchor
      getter timestamp_replica_id : ReplicaId
      getter timestamp_value : Lamport::Seq
      getter offset : UInt32
      getter bias : Bias
      getter buffer_id : BufferId

      def initialize(
        @timestamp_replica_id : ReplicaId,
        @timestamp_value : Lamport::Seq,
        @offset : UInt32,
        @bias : Bias,
        @buffer_id : BufferId,
      )
      end

      def self.new(timestamp : Lamport, offset : UInt32, bias : Bias, buffer_id : BufferId) : Anchor
        Anchor.new(timestamp.replica_id, timestamp.value, offset, bias, buffer_id)
      end

      def self.min_for_buffer(buffer_id : BufferId) : Anchor
        Anchor.new(Lamport::MIN.replica_id, Lamport::MIN.value, 0u32, Bias::Left, buffer_id)
      end

      def self.max_for_buffer(buffer_id : BufferId) : Anchor
        Anchor.new(Lamport::MAX.replica_id, Lamport::MAX.value, UInt32::MAX, Bias::Right, buffer_id)
      end

      def timestamp : Lamport
        Lamport.new(@timestamp_replica_id, @timestamp_value)
      end

      def min? : Bool
        timestamp == Lamport::MIN && @offset == 0u32 && @bias == Bias::Left
      end

      def max? : Bool
        timestamp == Lamport::MAX && @offset == UInt32::MAX && @bias == Bias::Right
      end

      def opaque_id : Bytes
        io = IO::Memory.new
        io.write_bytes(@buffer_id.value, IO::ByteFormat::LittleEndian)
        io.write_bytes(@offset, IO::ByteFormat::LittleEndian)
        io.write_bytes(@timestamp_value, IO::ByteFormat::LittleEndian)
        io.write_bytes(@timestamp_replica_id.value, IO::ByteFormat::LittleEndian)
        io.write_byte(@bias.value.to_u8)
        io.write_byte(0u8)
        io.to_slice
      end
    end
  end
end
