# src/delta_db/fragment_index.cr
module DeltaDB
  uuid_id FragmentId
  uuid_id InsertionId

  struct Length
    include Comparable(Length)

    getter value : UInt32

    def initialize(@value : UInt32)
    end

    def <=>(other : Length) : Int32
      @value <=> other.value
    end
  end

  enum LiteralOrigin
    Original
    Inserted
  end

  struct FragmentAlias
    getter fragment_id : FragmentId
    getter span : Range(UInt32, UInt32)

    def initialize(@fragment_id : FragmentId, @span : Range(UInt32, UInt32))
    end
  end

  struct AliasSpan
    getter start : UInt32
    getter end : UInt32

    def initialize(@start : UInt32, @end : UInt32)
    end
  end

  struct ContentSplice
    getter range : Range(UInt32, UInt32)
    getter text : String

    def initialize(@range : Range(UInt32, UInt32), @text : String)
    end
  end

  struct EditPlan
    getter fragment_id : FragmentId
    getter splices : Array(ContentSplice)

    def initialize(@fragment_id : FragmentId, @splices : Array(ContentSplice) = [] of ContentSplice)
    end
  end

  struct AppliedFragmentEdit
    getter fragment_id : FragmentId
    getter range : Range(UInt32, UInt32)
    getter text : String

    def initialize(@fragment_id : FragmentId, @range : Range(UInt32, UInt32), @text : String)
    end
  end

  class FragmentRecord
    getter id : FragmentId
    property text : String
    getter origin : LiteralOrigin

    def initialize(@id : FragmentId, @text : String, @origin : LiteralOrigin)
    end
  end

  class FragmentIndex
    getter records : Hash(FragmentId, FragmentRecord)
    getter aliases : Hash(FragmentId, FragmentAlias)

    def initialize
      @records = {} of FragmentId => FragmentRecord
      @aliases = {} of FragmentId => FragmentAlias
    end

    def self.from_fragments(fragments : Array(Fragment)) : FragmentIndex
      index = FragmentIndex.new
      fragments.each { |fragment| index.insert(fragment.text, origin: fragment.visible ? LiteralOrigin::Inserted : LiteralOrigin::Original) }
      index
    end

    def insert(text : String, id : FragmentId = FragmentId.random, origin : LiteralOrigin = LiteralOrigin::Inserted) : FragmentRecord
      if @records.has_key?(id)
        raise ArgumentError.new("fragment already exists: #{id}")
      end
      record = FragmentRecord.new(id, text, origin)
      @records[id] = record
      @aliases[id] = FragmentAlias.new(id, 0u32...text.bytesize.to_u32)
      record
    end

    def delete(id : FragmentId) : FragmentRecord?
      @aliases.delete(id)
      @records.delete(id)
    end

    def resolve(id : FragmentId) : String
      record = @records.fetch(id) { raise ArgumentError.new("missing fragment: #{id}") }
      span = @aliases.fetch(id).span
      if span.begin > span.end || span.end > record.text.bytesize
        raise ArgumentError.new("alias span outside fragment: #{id}")
      end
      record.text.byte_slice(span.begin.to_i32, (span.end - span.begin).to_i32)
    end

    def splice(id : FragmentId, range : Range(UInt32, UInt32), text : String) : String
      record = @records.fetch(id) { raise ArgumentError.new("missing fragment: #{id}") }
      if range.begin > range.end || range.end > record.text.bytesize
        raise ArgumentError.new("splice range outside fragment: #{id}")
      end
      record.text.byte_slice(0, range.begin.to_i32) + text + record.text.byte_slice(range.end.to_i32)
    end

    def apply(plan : EditPlan) : Array(AppliedFragmentEdit)
      ranges = plan.splices.map(&.range)
      unless DeltaDB.validate_edit_ranges(ranges)
        raise ArgumentError.new("edit ranges must be sorted and non-overlapping")
      end
      unless @records.has_key?(plan.fragment_id)
        raise ArgumentError.new("missing fragment: #{plan.fragment_id}")
      end

      plan.splices.reverse_each do |splice|
        updated = splice(plan.fragment_id, splice.range, splice.text)
        record = @records[plan.fragment_id]
        record.text = updated
        @aliases[plan.fragment_id] = FragmentAlias.new(plan.fragment_id, 0u32...updated.bytesize.to_u32)
      end
      plan.splices.map { |splice| AppliedFragmentEdit.new(plan.fragment_id, splice.range, splice.text) }
    end
  end

  def self.validate_edit_ranges(ranges : Array(Range(UInt32, UInt32))) : Bool
    ranges.each_with_index do |range, index|
      return false if range.end < range.begin
      if index > 0 && ranges[index - 1].end > range.begin
        return false
      end
    end
    true
  end
end
