# src/delta_db/replication/pack_codec.cr
module DeltaDB
  module Replication
    module PackCodec
      def self.encode(pack : Pack) : String
        PackDocument.new(
          pack.id,
          Checkpoint::Codec.version_document(pack.from_version),
          Checkpoint::Codec.version_document(pack.to_version),
          Checkpoint::Codec.document(pack.snapshot),
          pack.sealed,
        ).to_json
      end

      def self.decode(text : String) : Pack
        document = PackDocument.from_json(text)
        snapshot = Checkpoint::Codec.snapshot(document.checkpoint)
        Pack.new(
          document.id,
          snapshot.history_id,
          Checkpoint::Codec.version_snapshot(document.from_version),
          Checkpoint::Codec.version_snapshot(document.to_version),
          snapshot,
          document.sealed,
        )
      end
    end
  end
end
