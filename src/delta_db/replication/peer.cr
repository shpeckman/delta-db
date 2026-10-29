# src/delta_db/replication/peer.cr
module DeltaDB
  module Replication
    class Peer
      getter packs : Hash(String, Pack)

      def initialize
        @histories = {} of HistoryId => History::Dag
        @packs = {} of String => Pack
      end

      def history(id : HistoryId) : History::Dag
        @histories[id] ||= History::Dag.new(id)
      end

      def install_pack(pack : Pack) : Nil
        return if @packs.has_key?(pack.id)
        unless pack.sealed
          raise ArgumentError.new("replication pack is not sealed: #{pack.id}")
        end
        history(pack.history_id).merge_checkpoint(pack.snapshot)
        @packs[pack.id] = pack
      end

      def pack_for_history(id : HistoryId, from_version : History::Version) : Pack
        Pack.from(history(id), from_version)
      end

      def reset_timeline(id : HistoryId, timeline : TimelineId, origin : History::Version) : TimelineId
        history(id).reset_timeline(timeline, origin)
      end

      def fork_timeline(id : HistoryId, source : TimelineId, target : TimelineId) : History::Timeline
        history(id).fork_timeline(source, target)
      end
    end
  end
end
