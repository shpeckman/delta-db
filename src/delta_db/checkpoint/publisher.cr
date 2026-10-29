# src/delta_db/checkpoint/publisher.cr
module DeltaDB
  module Checkpoint
    class Publisher
      getter publications : Hash(String, Publication)

      def initialize
        @publications = {} of String => Publication
      end

      def prepare(dag : History::Dag) : Publication
        snapshot = dag.checkpoint
        publication = Publication.new(UUID.random.to_s, dag.history_id, dag.timeline_version, Codec.encode(snapshot))
        @publications[publication.id] = publication
        publication
      end

      def publish(id : String) : Publication
        publication = required(id)
        unless publication.phase.prepared? || publication.phase.publishing?
          raise ArgumentError.new("checkpoint is not ready to publish: #{publication.phase}")
        end
        publication.phase = Publication::Phase::Published
        publication
      end

      def install(id : String) : History::Dag
        publication = required(id)
        unless publication.phase.published?
          raise ArgumentError.new("checkpoint is not published: #{publication.phase}")
        end
        begin
          snapshot = Codec.decode(publication.encoded)
          dag = History::Dag.from_snapshot(snapshot)
          publication.phase = Publication::Phase::Installed
          dag
        rescue error
          publication.phase = Publication::Phase::Failed
          publication.last_error = error.message
          raise error
        end
      end

      def fail(id : String, message : String) : Publication
        publication = required(id)
        publication.phase = Publication::Phase::Failed
        publication.last_error = message
        publication
      end

      def get(id : String) : Publication?
        @publications[id]?
      end

      def list : Array(Publication)
        @publications.values.sort_by(&.id)
      end

      private def required(id : String) : Publication
        @publications.fetch(id) { raise ArgumentError.new("missing checkpoint publication: #{id}") }
      end
    end
  end
end
