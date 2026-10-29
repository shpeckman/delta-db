# src/delta_db/replication/pack_codec.cr
module DeltaDB
  module Replication
    module PackCodec
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
  end
end
