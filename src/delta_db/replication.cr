# src/delta_db/replication.cr
module DeltaDB
  class ReplicationPack
    getter id : String
    getter history_id : HistoryId
    getter from_version : HistoryVersion
    getter to_version : HistoryVersion
    getter snapshot : HistoryDagSnapshot
    property sealed : Bool

    def initialize(@id : String, @history_id : HistoryId, @from_version : HistoryVersion, @to_version : HistoryVersion, @snapshot : HistoryDagSnapshot, @sealed : Bool = true)
    end
  end

  struct ReplicationPackDocument
    include JSON::Serializable

    getter id : String
    getter from_version : Array(CheckpointBatchIdDocument)
    getter to_version : Array(CheckpointBatchIdDocument)
    getter checkpoint : CheckpointDocument
    getter sealed : Bool

    def initialize(@id : String, @from_version : Array(CheckpointBatchIdDocument), @to_version : Array(CheckpointBatchIdDocument), @checkpoint : CheckpointDocument, @sealed : Bool)
    end
  end

  module ReplicationPackCodec
    def self.encode(pack : ReplicationPack) : String
      ReplicationPackDocument.new(
        pack.id,
        CheckpointCodec.version_document(pack.from_version),
        CheckpointCodec.version_document(pack.to_version),
        CheckpointCodec.document(pack.snapshot),
        pack.sealed,
      ).to_json
    end

    def self.decode(text : String) : ReplicationPack
      document = ReplicationPackDocument.from_json(text)
      snapshot = CheckpointCodec.snapshot(document.checkpoint)
      ReplicationPack.new(
        document.id,
        snapshot.history_id,
        CheckpointCodec.version_snapshot(document.from_version),
        CheckpointCodec.version_snapshot(document.to_version),
        snapshot,
        document.sealed,
      )
    end
  end

  module ReplicationPacker
    def self.pack(dag : HistoryDag, from_version : HistoryVersion) : ReplicationPack
      ReplicationPack.new(UUID.random.to_s, dag.history_id, from_version, dag.timeline_version, dag.checkpoint)
    end
  end

  enum ReplicationOutboxState
    Pending
    Sending
    Acknowledged
    Failed
  end

  class ReplicationOutboxEntry
    getter pack : ReplicationPack
    property state : ReplicationOutboxState
    property last_error : String?

    def initialize(@pack : ReplicationPack, @state : ReplicationOutboxState = ReplicationOutboxState::Pending, @last_error : String? = nil)
    end

    def id : String
      @pack.id
    end
  end

  class ReplicationOutbox
    def initialize(@storage : Storage)
    end

    def append(pack : ReplicationPack) : ReplicationOutboxEntry
      entry = ReplicationOutboxEntry.new(pack)
      @storage.insert_replication_outbox(entry)
      entry
    end

    def pending : Array(ReplicationOutboxEntry)
      @storage.replication_outbox_entries(ReplicationOutboxState::Pending)
    end

    def size : Int32
      @storage.replication_outbox_size
    end

    def acknowledge(id : String) : Nil
      @storage.update_replication_outbox_state(id, ReplicationOutboxState::Acknowledged)
    end

    def fail(id : String, message : String) : Nil
      @storage.update_replication_outbox_state(id, ReplicationOutboxState::Failed, message)
    end

    def retry(id : String) : Nil
      @storage.update_replication_outbox_state(id, ReplicationOutboxState::Pending)
    end
  end

  class RemotePeer
    getter packs : Hash(String, ReplicationPack)

    def initialize
      @histories = {} of HistoryId => HistoryDag
      @packs = {} of String => ReplicationPack
    end

    def history(id : HistoryId) : HistoryDag
      @histories[id] ||= HistoryDag.new(id)
    end

    def install_pack(pack : ReplicationPack) : Nil
      return if @packs.has_key?(pack.id)
      unless pack.sealed
        raise ArgumentError.new("replication pack is not sealed: #{pack.id}")
      end
      history(pack.history_id).merge_checkpoint(pack.snapshot)
      @packs[pack.id] = pack
    end

    def pack_for_history(id : HistoryId, from_version : HistoryVersion) : ReplicationPack
      ReplicationPacker.pack(history(id), from_version)
    end

    def reset_timeline(id : HistoryId, timeline : TimelineId, origin : HistoryVersion) : TimelineId
      history(id).reset_timeline(timeline, origin)
    end

    def fork_timeline(id : HistoryId, source : TimelineId, target : TimelineId) : HistoryTimeline
      history(id).fork_timeline(source, target)
    end
  end

  enum HistoryConnectionStatus
    Offline
    Syncing
    Synced
    Error
  end

  class HistoryConnectionState
    getter history_id : HistoryId
    property local_version : HistoryVersion
    property remote_version : HistoryVersion
    property reset_generation : UInt32
    property status : HistoryConnectionStatus
    property last_error : String?

    def initialize(
      @history_id : HistoryId,
      @local_version : HistoryVersion = HistoryVersion.new,
      @remote_version : HistoryVersion = HistoryVersion.new,
      @reset_generation : UInt32 = 0u32,
      @status : HistoryConnectionStatus = HistoryConnectionStatus::Offline,
      @last_error : String? = nil,
    )
    end
  end

  class RemoteSync
    getter outbox : ReplicationOutbox

    def initialize(@storage : Storage, @remote : RemotePeer)
      @outbox = ReplicationOutbox.new(@storage)
      @states = {} of HistoryId => HistoryConnectionState
    end

    def push_history(dag : HistoryDag) : HistoryConnectionState
      state = connection_state(dag.history_id)
      state.status = HistoryConnectionStatus::Syncing
      save_state(state)
      pack = ReplicationPacker.pack(dag, state.remote_version)
      entry = @outbox.append(pack)
      begin
        @remote.install_pack(pack)
        @outbox.acknowledge(entry.id)
        state.local_version = dag.timeline_version
        state.remote_version = @remote.history(dag.history_id).timeline_version
        state.status = HistoryConnectionStatus::Synced
        state.last_error = nil
      rescue error
        @outbox.fail(entry.id, error.message || error.class.name)
        fail_history(dag.history_id, error)
        raise error
      end
      save_state(state)
      state
    end

    def pull_history(dag : HistoryDag) : HistoryConnectionState
      state = connection_state(dag.history_id)
      pack = @remote.pack_for_history(dag.history_id, state.local_version)
      dag.merge_checkpoint(pack.snapshot)
      state.local_version = dag.timeline_version
      state.remote_version = @remote.history(dag.history_id).timeline_version
      state.status = HistoryConnectionStatus::Synced
      state.last_error = nil
      save_state(state)
      state
    end

    def sync_history(dag : HistoryDag) : HistoryConnectionState
      push_history(dag)
      pull_history(dag)
    end

    def retry_history(dag : HistoryDag) : HistoryConnectionState
      state = connection_state(dag.history_id)
      state.status = HistoryConnectionStatus::Syncing
      state.last_error = nil
      save_state(state)
      sync_history(dag)
    rescue error
      fail_history(dag.history_id, error)
      raise error
    end

    def reset_local_timeline(dag : HistoryDag, timeline : TimelineId, origin : HistoryVersion) : TimelineId
      reset = dag.reset_timeline(timeline, origin)
      @remote.reset_timeline(dag.history_id, timeline, origin)
      state = connection_state(dag.history_id)
      state.reset_generation = reset.generation
      save_state(state)
      sync_history(dag)
      reset
    end

    def fork_remote_timeline(dag : HistoryDag, source : TimelineId, target : TimelineId) : HistoryTimeline
      forked = @remote.fork_timeline(dag.history_id, source, target)
      pull_history(dag)
      dag.timelines[target]
    end

    def connection_state(history_id : HistoryId) : HistoryConnectionState
      @states[history_id] ||= @storage.load_history_connection_state(history_id) || HistoryConnectionState.new(history_id)
    end

    private def save_state(state : HistoryConnectionState) : Nil
      @states[state.history_id] = state
      @storage.upsert_history_connection_state(state)
    end

    private def fail_history(history_id : HistoryId, error : Exception) : Nil
      state = connection_state(history_id)
      state.status = HistoryConnectionStatus::Error
      state.last_error = error.message || error.class.name
      save_state(state)
    end
  end
end
