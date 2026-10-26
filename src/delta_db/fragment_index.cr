module DeltaDB
  # Identifier for a text fragment (a UUID-backed newtype).
  #
  # Recovered from `deltadb::fragment_index::FragmentId<DeltaId>`; the generic
  # `DeltaId`/`LocalDeltaId` parameter is elided in this clean-room port.
  uuid_id FragmentId

  # Identifier for a text insertion (a UUID-backed newtype).
  #
  # Recovered from `deltadb::text::InsertionId<DeltaId>`.
  uuid_id InsertionId

  # A byte length within a fragment index.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::Length`.
  struct Length
    include Comparable(Length)

    getter value : UInt32

    def initialize(@value : UInt32)
    end

    def <=>(other : Length) : Int32
      @value <=> other.value
    end
  end

  # Where a fragment's literal text originated.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::LiteralOrigin`.
  enum LiteralOrigin
    Original
    Inserted
  end

  # An alias of a fragment over a byte span (for edit planning).
  #
  # Clean-room reconstruction of `deltadb::fragment_index::FragmentAlias`.
  struct FragmentAlias
    getter fragment_id : FragmentId
    getter span : Range(UInt32, UInt32)

    def initialize(@fragment_id : FragmentId, @span : Range(UInt32, UInt32))
    end
  end

  # A span over aliased fragments.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::AliasSpan`.
  struct AliasSpan
    getter start : UInt32
    getter end : UInt32

    def initialize(@start : UInt32, @end : UInt32)
    end
  end

  # A splice of content over a byte range.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::ContentSplice`.
  struct ContentSplice
    getter range : Range(UInt32, UInt32)
    getter text : String

    def initialize(@range : Range(UInt32, UInt32), @text : String)
    end
  end

  # A plan of edits to apply to fragments.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::EditPlan`.
  struct EditPlan
    getter splices : Array(ContentSplice)

    def initialize(@splices : Array(ContentSplice) = [] of ContentSplice)
    end
  end

  # An edit applied to a specific fragment.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::AppliedFragmentEdit`.
  struct AppliedFragmentEdit
    getter fragment_id : FragmentId
    getter range : Range(UInt32, UInt32)
    getter text : String

    def initialize(@fragment_id : FragmentId, @range : Range(UInt32, UInt32), @text : String)
    end
  end

  # Validate that edit ranges are sorted and non-overlapping.
  #
  # Clean-room reconstruction of `deltadb::fragment_index::validate_edit_ranges`.
  def self.validate_edit_ranges(ranges : Array(Range(UInt32, UInt32))) : Bool
    sorted = ranges.sort_by(&.begin)
    (sorted.size - 1).times do |i|
      return false if sorted[i].end > sorted[i + 1].begin
    end
    true
  end
end
