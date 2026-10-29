# src/delta_db/history/version.cr
module DeltaDB
  module History
    struct Version
      getter ids : Array(DeltaBatchId)

      def initialize(ids : Enumerable(DeltaBatchId) = [] of DeltaBatchId)
        @ids = ids.to_a.sort.uniq
      end

      def self.from_id(id : DeltaBatchId) : Version
        new([id])
      end

      def self.from_ids(ids : Enumerable(DeltaBatchId)) : Version
        new(ids)
      end

      def self.decode_version_text(text : String, actors : Hash(Int64, TimelineId)) : Version
        return new if text.empty?

        ids = text.split(',').map do |entry|
          parts = entry.split(':')
          unless parts.size == 2
            raise ArgumentError.new("invalid history version entry: #{entry.inspect}")
          end

          actor = parts[0].to_i64
          timeline = actors.fetch(actor) do
            raise ArgumentError.new("unknown actor ordinal: #{actor}")
          end
          DeltaBatchId.new(timeline.uuid, parts[1].to_u64)
        end
        new(ids)
      end

      def empty? : Bool
        @ids.empty?
      end

      def size : Int32
        @ids.size
      end

      def contains?(id : DeltaBatchId) : Bool
        @ids.includes?(id)
      end

      def union(id : DeltaBatchId) : Version
        contains?(id) ? self : Version.new(@ids.dup << id)
      end

      def union(other : Version) : Version
        Version.new(@ids + other.ids)
      end

      def encode_version_text(actors : Hash(UUID, Int64)) : String
        @ids.map do |id|
          actor = actors.fetch(id.uuid) do
            raise ArgumentError.new("missing actor ordinal for timeline: #{id.uuid}")
          end
          "#{actor}:#{id.ordinal}"
        end.join(',')
      end

      def to_s(io : IO) : Nil
        @ids.join(io, ',', &.to_s(io))
      end
    end
  end
end
