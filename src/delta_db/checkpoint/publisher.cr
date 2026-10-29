# src/delta_db/checkpoint/publisher.cr
module DeltaDB
  module Checkpoint
    class Publisher
      getter publications : Hash(String, CheckpointPublication)

      def initialize
        @publications = {} of String => CheckpointPublication
      end

      def prepare(dag : HistoryDag) : CheckpointPublication
        snapshot = dag.checkpoint
        publication = CheckpointPublication.new(UUID.random.to_s, dag.history_id, dag.timeline_version, CheckpointCodec.encode(snapshot))
        @publications[publication.id] = publication
        publication
      end

      def publish(id : String) : CheckpointPublication
        publication = required(id)
        unless publication.phase.prepared? || publication.phase.publishing?
          raise ArgumentError.new("checkpoint is not ready to publish: #{publication.phase}")
        end
        publication.phase = CheckpointPublicationPhase::Published
        publication
      end

      def install(id : String) : HistoryDag
        publication = required(id)
        unless publication.phase.published?
          raise ArgumentError.new("checkpoint is not published: #{publication.phase}")
        end
        begin
          snapshot = CheckpointCodec.decode(publication.encoded)
          dag = HistoryDag.from_snapshot(snapshot)
          publication.phase = CheckpointPublicationPhase::Installed
          dag
        rescue error
          publication.phase = CheckpointPublicationPhase::Failed
          publication.last_error = error.message
          raise error
        end
      end

      def fail(id : String, message : String) : CheckpointPublication
        publication = required(id)
        publication.phase = CheckpointPublicationPhase::Failed
        publication.last_error = message
        publication
      end

      def get(id : String) : CheckpointPublication?
        @publications[id]?
      end

      def list : Array(CheckpointPublication)
        @publications.values.sort_by(&.id)
      end

      private def required(id : String) : CheckpointPublication
        @publications.fetch(id) { raise ArgumentError.new("missing checkpoint publication: #{id}") }
      end
    end
  end
end
