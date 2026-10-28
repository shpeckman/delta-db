# src/delta_db/history_engine.cr
module DeltaDB
  struct DeltaRun
    getter actor : ReplicaId
    getter timestamp : Lamport
    getter delta_ids : Array(DeltaId)

    def initialize(@actor : ReplicaId, @timestamp : Lamport, @delta_ids : Array(DeltaId))
    end
  end

  struct HistoryRecord
    getter history_id : HistoryId
    getter timeline_id : TimelineId
    getter target_version : HistoryVersion

    def initialize(@history_id : HistoryId, @timeline_id : TimelineId, @target_version : HistoryVersion)
    end
  end

  struct Checkpoint
    getter version : HistoryVersion
    getter registers : Array(AnyRegister(String))
    getter maps : Array(Map)
    getter buffers : Array(Buffer)
    getter worktrees : Array(String)
    getter text_only_object : String?

    def initialize(
      @version : HistoryVersion,
      @registers : Array(AnyRegister(String)) = [] of AnyRegister(String),
      @maps : Array(Map) = [] of Map,
      @buffers : Array(Buffer) = [] of Buffer,
      @worktrees : Array(String) = [] of String,
      @text_only_object : String? = nil,
    )
    end
  end

  struct HistoryDeltaBatch
    getter id : DeltaBatchId
    getter timeline : TimelineId
    getter actor : ActorUuid
    getter parents : HistoryVersion
    getter deltas : Array(Delta)
    getter epoch : UInt64

    def initialize(
      @id : DeltaBatchId,
      @timeline : TimelineId,
      @actor : ActorUuid,
      @parents : HistoryVersion = HistoryVersion.new,
      @deltas : Array(Delta) = [] of Delta,
      @epoch : UInt64 = 0u64,
    )
    end

    def causal_parent : HistoryVersion
      @parents
    end
  end

  struct HistoryTimeline
    getter id : TimelineId
    property head : HistoryVersion
    getter origin : HistoryVersion
    getter parent : TimelineId?
    getter reset_generation : UInt32

    def initialize(
      @id : TimelineId,
      @head : HistoryVersion = HistoryVersion.new,
      @origin : HistoryVersion = HistoryVersion.new,
      @parent : TimelineId? = nil,
      @reset_generation : UInt32 = id.generation,
    )
    end
  end

  struct HistoryEpoch
    getter epoch : UInt64
    getter start_version : HistoryVersion

    def initialize(@epoch : UInt64, @start_version : HistoryVersion)
    end
  end

  struct HistoryDagSnapshot
    getter history_id : HistoryId
    getter batches : Array(HistoryDeltaBatch)
    getter timelines : Array(HistoryTimeline)
    getter epochs : Array(HistoryEpoch)
    getter max_timestamp : UInt64
    getter epoch_count : UInt64

    def initialize(
      @history_id : HistoryId,
      @batches : Array(HistoryDeltaBatch) = [] of HistoryDeltaBatch,
      @timelines : Array(HistoryTimeline) = [] of HistoryTimeline,
      @epochs : Array(HistoryEpoch) = [] of HistoryEpoch,
      @max_timestamp : UInt64 = 0u64,
      @epoch_count : UInt64 = 0u64,
    )
    end
  end

  class HistoryDag
    getter history_id : HistoryId
    getter batches : Hash(DeltaBatchId, HistoryDeltaBatch)
    getter timelines : Hash(TimelineId, HistoryTimeline)
    getter epochs : Array(HistoryEpoch)
    getter max_timestamp : UInt64
    getter epoch_count : UInt64

    def initialize(@history_id : HistoryId)
      @batches = Hash(DeltaBatchId, HistoryDeltaBatch).new
      @timelines = Hash(TimelineId, HistoryTimeline).new
      @epochs = [] of HistoryEpoch
      @max_timestamp = 0u64
      @epoch_count = 0u64
    end

    def self.from_snapshot(snapshot : HistoryDagSnapshot) : HistoryDag
      dag = HistoryDag.new(snapshot.history_id)
      dag.install_checkpoint(snapshot)
      dag
    end

    def create_timeline(id : TimelineId, origin : HistoryVersion = HistoryVersion.new, parent : TimelineId? = nil) : HistoryTimeline
      if @timelines.has_key?(id)
        raise ArgumentError.new("timeline already exists: #{id}")
      end
      validate_version(origin)
      timeline = HistoryTimeline.new(id, origin, origin, parent)
      @timelines[id] = timeline
      timeline
    end

    def insert_globally(batch : HistoryDeltaBatch) : Nil
      if existing = @batches[batch.id]?
        return if existing == batch
        raise ArgumentError.new("conflicting batch id: #{batch.id}")
      end
      if batch.parents.contains?(batch.id)
        raise ArgumentError.new("batch cannot be its own parent: #{batch.id}")
      end
      validate_version(batch.parents)
      unless @timelines.has_key?(batch.timeline)
        create_timeline(batch.timeline, batch.parents)
      end

      @batches[batch.id] = batch
      @max_timestamp = Math.max(@max_timestamp, batch.id.ordinal)
      @epoch_count = Math.max(@epoch_count, batch.epoch + 1u64)
      timeline = @timelines[batch.timeline]
      timeline.head = timeline.head.union(HistoryVersion.from_id(batch.id))
    end

    def insert_on_timeline(batch : HistoryDeltaBatch) : Nil
      timeline = @timelines[batch.timeline]? || create_timeline(batch.timeline, batch.parents)
      unless version_reaches(timeline.head, batch.parents)
        raise ArgumentError.new("batch does not extend timeline head: #{batch.timeline}")
      end

      insert_globally(batch)
      timeline.head = HistoryVersion.from_id(batch.id)
    end

    def advance_timeline(batch : HistoryDeltaBatch) : Nil
      insert_on_timeline(batch)
    end

    def reset_timeline(id : TimelineId, origin : HistoryVersion) : TimelineId
      source = @timelines.fetch(id) { raise ArgumentError.new("unknown timeline: #{id}") }
      reset_id = TimelineId.new(id.uuid, source.reset_generation + 1u32)
      create_timeline(reset_id, origin, id)
      reset_id
    end

    def fork_timeline(source_id : TimelineId, target_id : TimelineId, at : HistoryVersion? = nil) : HistoryTimeline
      source = @timelines.fetch(source_id) { raise ArgumentError.new("unknown timeline: #{source_id}") }
      create_timeline(target_id, at || source.head, source_id)
    end

    def timeline_version(id : TimelineId) : HistoryVersion
      @timelines.fetch(id) { raise ArgumentError.new("unknown timeline: #{id}") }.head
    end

    def timeline_version : HistoryVersion
      HistoryVersion.from_ids(@timelines.values.flat_map(&.head.ids))
    end

    def timeline_ids : Array(TimelineId)
      @timelines.keys.sort
    end

    def timeline_parent_id(id : TimelineId) : TimelineId?
      @timelines.fetch(id) { raise ArgumentError.new("unknown timeline: #{id}") }.parent
    end

    def timeline_lineage(id : TimelineId) : Array(TimelineId)
      lineage = [] of TimelineId
      current : TimelineId? = id
      while current
        lineage << current
        current = timeline_parent_id(current)
      end
      lineage
    end

    def contains_version(version : HistoryVersion) : Bool
      version.ids.all? { |id| @batches.has_key?(id) }
    end

    def contains_version(version : HistoryVersion, timeline_id : TimelineId) : Bool
      reachable = ancestor_ids(timeline_version(timeline_id))
      version.ids.all? { |id| reachable.includes?(id) }
    end

    def version_reaches(ancestor : HistoryVersion, descendant : HistoryVersion) : Bool
      return true if ancestor.empty?
      return false if descendant.empty?
      reachable = ancestor_ids(descendant)
      ancestor.ids.all? { |id| reachable.includes?(id) }
    end

    def version_reached_by_all(ancestor : HistoryVersion, versions : Array(HistoryVersion)) : Bool
      versions.all? { |version| version_reaches(ancestor, version) }
    end

    def versions_reaching_ancestor(ancestor : HistoryVersion, versions : Array(HistoryVersion)) : Array(HistoryVersion)
      versions.select { |version| version_reaches(ancestor, version) }
    end

    def ancestors(version : HistoryVersion) : HistoryVersion
      HistoryVersion.from_ids(ancestor_ids(version))
    end

    def common_ancestor(a : HistoryVersion, b : HistoryVersion) : HistoryVersion
      left = ancestor_ids(a)
      right = ancestor_ids(b)
      shared = left.select { |id| right.includes?(id) }
      maximal = shared.reject do |candidate|
        shared.any? { |other| candidate != other && reaches_id?(candidate, other) }
      end
      HistoryVersion.from_ids(maximal)
    end

    def common_ancestor_since_epoch(a : HistoryVersion, b : HistoryVersion, epoch : UInt64) : HistoryVersion
      left = ancestor_ids(a)
      right = ancestor_ids(b)
      shared = left.select do |id|
        right.includes?(id) && (@batches[id]?.try(&.epoch) || 0u64) >= epoch
      end
      maximal = shared.reject do |candidate|
        shared.any? { |other| candidate != other && reaches_id?(candidate, other) }
      end
      HistoryVersion.from_ids(maximal)
    end

    def dominator(a : HistoryVersion, b : HistoryVersion) : HistoryVersion
      common_ancestor(a, b)
    end

    def branch_point_for_timelines(a : TimelineId, b : TimelineId) : HistoryVersion
      common_ancestor(timeline_version(a), timeline_version(b))
    end

    def delta_headers_difference(a : HistoryVersion, b : HistoryVersion) : Array(HistoryDeltaBatch)
      left = ancestor_ids(a)
      right = ancestor_ids(b)
      ids = left.reject { |id| right.includes?(id) }
      ids.sort.map { |id| @batches[id] }
    end

    def deltas_between(a : HistoryVersion, b : HistoryVersion) : Array(HistoryDeltaBatch)
      delta_headers_difference(a, b)
    end

    def begin_epoch : HistoryEpoch
      @epoch_count += 1u64
      epoch = HistoryEpoch.new(@epoch_count, timeline_version)
      @epochs << epoch
      epoch
    end

    def epoch_of_version(version : HistoryVersion) : UInt64
      version.ids.max_of? { |id| @batches[id]?.try(&.epoch) || 0u64 } || 0u64
    end

    def checkpoint : HistoryDagSnapshot
      HistoryDagSnapshot.new(
        @history_id,
        @batches.values.sort_by(&.id),
        @timelines.values.sort_by(&.id),
        @epochs.dup,
        @max_timestamp,
        @epoch_count,
      )
    end

    def install_checkpoint(snapshot : HistoryDagSnapshot) : Nil
      unless snapshot.history_id == @history_id
        raise ArgumentError.new("checkpoint history does not match")
      end

      @batches.clear
      @timelines.clear
      @epochs = snapshot.epochs.dup
      @max_timestamp = snapshot.max_timestamp
      @epoch_count = snapshot.epoch_count
      snapshot.timelines.each { |timeline| @timelines[timeline.id] = timeline }
      snapshot.batches.sort_by(&.id).each { |batch| insert_globally(batch) }
      snapshot.timelines.each do |timeline|
        @timelines[timeline.id].head = timeline.head
      end
    end

    private def validate_version(version : HistoryVersion) : Nil
      version.ids.each do |id|
        unless @batches.has_key?(id)
          raise ArgumentError.new("missing parent batch: #{id}")
        end
      end
    end

    private def ancestor_ids(version : HistoryVersion) : Array(DeltaBatchId)
      visited = Set(DeltaBatchId).new
      pending = version.ids.dup
      until pending.empty?
        id = pending.pop
        next if visited.includes?(id)
        visited << id
        if batch = @batches[id]?
          pending.concat(batch.parents.ids)
        end
      end
      visited.to_a.sort
    end

    private def reaches_id?(ancestor : DeltaBatchId, descendant : DeltaBatchId) : Bool
      return true if ancestor == descendant
      ancestor_ids(HistoryVersion.from_id(descendant)).includes?(ancestor)
    end
  end

  module MergeBaseResolver
    def self.merge_base(dag : HistoryDag, a : HistoryVersion, b : HistoryVersion) : HistoryVersion?
      base = dag.common_ancestor(a, b)
      base.empty? ? nil : base
    end

    def self.merge_base(a : HistoryVersion, b : HistoryVersion) : HistoryVersion?
      a == b ? a : nil
    end
  end
end
