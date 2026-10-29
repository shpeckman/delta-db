# src/delta_db/history/dag.cr
module DeltaDB
  module History
    class Dag
      getter history_id : HistoryId
      getter batches : Hash(DeltaBatchId, Batch)
      getter timelines : Hash(TimelineId, Timeline)
      getter epochs : Array(Epoch)
      getter max_timestamp : UInt64
      getter epoch_count : UInt64

      def initialize(@history_id : HistoryId)
        @batches = Hash(DeltaBatchId, Batch).new
        @timelines = Hash(TimelineId, Timeline).new
        @epochs = [] of Epoch
        @max_timestamp = 0u64
        @epoch_count = 0u64
      end

      def self.from_snapshot(snapshot : Snapshot) : Dag
        dag = Dag.new(snapshot.history_id)
        dag.install_checkpoint(snapshot)
        dag
      end

      def create_timeline(id : TimelineId, origin : Version = Version.new, parent : TimelineId? = nil) : Timeline
        if @timelines.has_key?(id)
          raise ArgumentError.new("timeline already exists: #{id}")
        end
        validate_version(origin)
        timeline = Timeline.new(id, origin, origin, parent)
        @timelines[id] = timeline
        timeline
      end

      def insert_globally(batch : Batch) : Nil
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
        @epoch_count = Math.max(@epoch_count, batch.epoch)
        timeline = @timelines[batch.timeline]
        head = version_reaches(timeline.head, batch.parents) ? Version.from_id(batch.id) : timeline.head.union(batch.id)
        @timelines[batch.timeline] = timeline.with_head(head)
      end

      def insert_on_timeline(batch : Batch) : Nil
        timeline = @timelines[batch.timeline]? || create_timeline(batch.timeline, batch.parents)
        unless version_reaches(timeline.head, batch.parents)
          raise ArgumentError.new("batch does not extend timeline head: #{batch.timeline}")
        end

        insert_globally(batch)
        @timelines[batch.timeline] = @timelines[batch.timeline].with_head(Version.from_id(batch.id))
      end

      def advance_timeline(batch : Batch) : Nil
        insert_on_timeline(batch)
      end

      def reset_timeline(id : TimelineId, origin : Version) : TimelineId
        source = @timelines.fetch(id) { raise NotFoundError.new("unknown timeline: #{id}") }
        reset_id = TimelineId.new(id.uuid, source.reset_generation + 1u32)
        create_timeline(reset_id, origin, id)
        reset_id
      end

      def fork_timeline(source_id : TimelineId, target_id : TimelineId, at : HistoryVersion? = nil) : Timeline
        source = @timelines.fetch(source_id) { raise NotFoundError.new("unknown timeline: #{source_id}") }
        create_timeline(target_id, at || source.head, source_id)
      end

      def timeline_version(id : TimelineId) : Version
        @timelines.fetch(id) { raise NotFoundError.new("unknown timeline: #{id}") }.head
      end

      def timeline_version : Version
        Version.from_ids(@timelines.values.flat_map(&.head.ids))
      end

      def timeline_ids : Array(TimelineId)
        @timelines.keys.sort
      end

      def timeline_parent_id(id : TimelineId) : TimelineId?
        @timelines.fetch(id) { raise NotFoundError.new("unknown timeline: #{id}") }.parent
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

      def contains_version(version : Version) : Bool
        version.ids.all? { |id| @batches.has_key?(id) }
      end

      def contains_version(version : Version, timeline_id : TimelineId) : Bool
        reachable = ancestor_ids(timeline_version(timeline_id))
        version.ids.all? { |id| reachable.includes?(id) }
      end

      def version_reaches(ancestor : Version, descendant : Version) : Bool
        return true if ancestor.empty?
        return false if descendant.empty?
        reachable = ancestor_ids(descendant)
        ancestor.ids.all? { |id| reachable.includes?(id) }
      end

      def version_reached_by_all(ancestor : Version, versions : Array(Version)) : Bool
        versions.all? { |version| version_reaches(ancestor, version) }
      end

      def versions_reaching_ancestor(ancestor : Version, versions : Array(Version)) : Array(Version)
        versions.select { |version| version_reaches(ancestor, version) }
      end

      def ancestors(version : Version) : Version
        Version.from_ids(ancestor_ids(version))
      end

      def common_ancestor(a : Version, b : Version) : Version
        return a if a == b

        left = ancestor_ids(a)
        right = ancestor_ids(b)
        shared = left.select { |id| right.includes?(id) }
        maximal = shared.reject do |candidate|
          shared.any? { |other| candidate != other && reaches_id?(candidate, other) }
        end
        Version.from_ids(maximal)
      end

      def common_ancestor_since_epoch(a : Version, b : Version, epoch : UInt64) : Version
        left = ancestor_ids(a)
        right = ancestor_ids(b)
        shared = left.select do |id|
          right.includes?(id) && (@batches[id]?.try(&.epoch) || 0u64) >= epoch
        end
        maximal = shared.reject do |candidate|
          shared.any? { |other| candidate != other && reaches_id?(candidate, other) }
        end
        Version.from_ids(maximal)
      end

      def dominator(a : Version, b : Version) : Version
        common_ancestor(a, b)
      end

      def branch_point_for_timelines(a : TimelineId, b : TimelineId) : Version
        common_ancestor(timeline_version(a), timeline_version(b))
      end

      def delta_headers_difference(a : Version, b : Version) : Array(Batch)
        left = ancestor_ids(a)
        right = ancestor_ids(b)
        ids = left.reject { |id| right.includes?(id) }
        ids.sort.map { |id| @batches[id] }
      end

      def deltas_between(a : Version, b : Version) : Array(Batch)
        delta_headers_difference(a, b)
      end

      def begin_epoch : Epoch
        @epoch_count += 1u64
        epoch = Epoch.new(@epoch_count, timeline_version)
        @epochs << epoch
        epoch
      end

      def epoch_of_version(version : Version) : UInt64
        version.ids.max_of? { |id| @batches[id]?.try(&.epoch) || 0u64 } || 0u64
      end

      def checkpoint : Snapshot
        Snapshot.new(
          @history_id,
          @batches.values.sort_by(&.id),
          @timelines.values.sort_by(&.id),
          @epochs.dup,
          @max_timestamp,
          @epoch_count,
        )
      end

      def install_checkpoint(snapshot : Snapshot) : Nil
        unless snapshot.history_id == @history_id
          raise ArgumentError.new("checkpoint history does not match")
        end

        @batches.clear
        @timelines.clear
        @epochs = snapshot.epochs.dup
        @max_timestamp = snapshot.max_timestamp
        @epoch_count = snapshot.epoch_count
        snapshot.timelines.each { |timeline| @timelines[timeline.id] = timeline }
        pending = snapshot.batches.dup
        until pending.empty?
          batch = pending.find { |candidate| candidate.parents.ids.all? { |id| @batches.has_key?(id) } }
          unless batch
            raise ArgumentError.new("checkpoint contains a missing or cyclic parent")
          end
          insert_globally(batch)
          pending.delete(batch)
        end
        snapshot.timelines.each do |timeline|
          @timelines[timeline.id] = @timelines[timeline.id].with_head(timeline.head)
        end
      end

      def merge_checkpoint(snapshot : Snapshot) : Nil
        unless snapshot.history_id == @history_id
          raise ArgumentError.new("checkpoint history does not match")
        end

        previous_heads = @timelines.transform_values(&.head)
        snapshot.timelines.each do |timeline|
          @timelines[timeline.id] ||= timeline
        end
        pending = snapshot.batches.reject { |batch| @batches.has_key?(batch.id) }
        until pending.empty?
          batch = pending.find { |candidate| candidate.parents.ids.all? { |id| @batches.has_key?(id) } }
          unless batch
            raise ArgumentError.new("checkpoint contains a missing or cyclic parent")
          end
          insert_globally(batch)
          pending.delete(batch)
        end
        snapshot.timelines.each do |timeline|
          previous = previous_heads[timeline.id]?
          @timelines[timeline.id] = @timelines[timeline.id].with_head(previous ? previous.union(timeline.head) : timeline.head)
        end
        snapshot.epochs.each do |epoch|
          @epochs << epoch unless @epochs.any? { |existing| existing.epoch == epoch.epoch }
        end
        @epochs.sort_by!(&.epoch)
        @max_timestamp = Math.max(@max_timestamp, snapshot.max_timestamp)
        @epoch_count = Math.max(@epoch_count, snapshot.epoch_count)
      end

      private def validate_version(version : Version) : Nil
        version.ids.each do |id|
          unless @batches.has_key?(id)
            raise ArgumentError.new("missing parent batch: #{id}")
          end
        end
      end

      private def ancestor_ids(version : Version) : Array(DeltaBatchId)
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
        ancestor_ids(Version.from_id(descendant)).includes?(ancestor)
      end
    end
  end
end
