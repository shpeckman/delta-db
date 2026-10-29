# src/delta_db/timeline_id.cr
require "uuid"

module DeltaDB
  # Identifies a timeline: a UUID plus a reset generation.
  #
  # Observed in the runtime log as `TimelineId(UUID.N)`.
  struct TimelineId
    include Comparable(TimelineId)

    getter uuid : UUID
    getter generation : UInt32

    def initialize(@uuid : UUID, @generation : UInt32 = 0u32)
    end

    def self.random : TimelineId
      TimelineId.new(UUID.random)
    end

    def self.parse(text : String) : TimelineId
      uuid, separator, generation = text.rpartition('.')
      return TimelineId.new(UUID.new(text)) if separator.empty?
      if uuid.empty? || generation.empty?
        raise ArgumentError.new("invalid timeline id: #{text.inspect}")
      end

      TimelineId.new(UUID.new(uuid), generation.to_u32)
    end

    def <=>(other : TimelineId) : Int32
      r = @uuid <=> other.uuid
      r == 0 ? @generation <=> other.generation : r
    end

    def to_s(io : IO) : Nil
      @uuid.to_s(io)
      io << '.' << @generation
    end
  end
end
