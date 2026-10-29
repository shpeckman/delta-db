# src/delta_db/fragment_index.cr
module DeltaDB
  class FragmentIndex
    DeltaDB.uuid_id Id

    enum Origin
      Original
      Inserted
    end

    getter records : Hash(Id, Record)
    getter aliases : Hash(Id, Alias)

    def initialize
      @records = {} of Id => Record
      @aliases = {} of Id => Alias
    end

    def self.from_fragments(fragments : Array(Text::Fragment)) : FragmentIndex
      index = FragmentIndex.new
      fragments.select(&.visible).each { |fragment| index.insert(fragment.text, origin: Origin::Inserted) }
      index
    end

    def insert(text : String, id : Id = Id.random, origin : Origin = Origin::Inserted) : Record
      if @records.has_key?(id)
        raise ArgumentError.new("fragment already exists: #{id}")
      end
      record = Record.new(id, text, origin)
      @records[id] = record
      @aliases[id] = Alias.new(id, 0u32...text.bytesize.to_u32)
      record
    end

    def delete(id : Id) : Record?
      @aliases.delete(id)
      @records.delete(id)
    end

    def resolve(id : Id) : String
      record = @records.fetch(id) { raise NotFoundError.new("missing fragment: #{id}") }
      span = @aliases[id].span
      if span.begin > span.end || span.end > record.text.bytesize
        raise ArgumentError.new("alias span outside fragment: #{id}")
      end
      record.text.byte_slice(span.begin.to_i32, (span.end - span.begin).to_i32)
    end

    def splice(id : Id, range : Range(UInt32, UInt32), text : String) : String
      record = @records.fetch(id) { raise NotFoundError.new("missing fragment: #{id}") }
      if range.begin > range.end || range.end > record.text.bytesize
        raise ArgumentError.new("splice range outside fragment: #{id}")
      end
      record.text.byte_slice(0, range.begin.to_i32) + text + record.text.byte_slice(range.end.to_i32)
    end

    def apply(plan : EditPlan) : Array(AppliedEdit)
      ranges = plan.splices.map(&.range)
      unless FragmentIndex.valid_ranges?(ranges)
        raise ArgumentError.new("edit ranges must be sorted and non-overlapping")
      end
      unless @records.has_key?(plan.fragment_id)
        raise NotFoundError.new("missing fragment: #{plan.fragment_id}")
      end

      plan.splices.reverse_each do |splice|
        updated = splice(plan.fragment_id, splice.range, splice.text)
        record = @records[plan.fragment_id]
        record.text = updated
        @aliases[plan.fragment_id] = Alias.new(plan.fragment_id, 0u32...updated.bytesize.to_u32)
      end
      plan.splices.map { |splice| AppliedEdit.new(plan.fragment_id, splice.range, splice.text) }
    end

    def self.valid_ranges?(ranges : Array(Range(UInt32, UInt32))) : Bool
      ranges.each_with_index do |range, index|
        return false if range.end < range.begin
        return false if index > 0 && ranges[index - 1].end > range.begin
      end
      true
    end
  end
end
