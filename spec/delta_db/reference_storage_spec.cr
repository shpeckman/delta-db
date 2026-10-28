# spec/delta_db/reference_storage_spec.cr
require "../spec_helper"

private alias ActorMaps = {Hash(UUID, Int64), Hash(Int64, DeltaDB::TimelineId)}

private def reference_actor_maps(database : DB::Database) : Hash(Int64, ActorMaps)
  maps = Hash(Int64, ActorMaps).new
  database.query("SELECT history_key, actor_ordinal, actor FROM history_actors") do |result_set|
    result_set.each do
      history_key = result_set.read(Int64)
      ordinal = result_set.read(Int64)
      timeline = DeltaDB::TimelineId.parse(result_set.read(String))
      by_uuid, by_ordinal = maps[history_key] ||= {
        {} of UUID => Int64,
        {} of Int64 => DeltaDB::TimelineId,
      }
      by_uuid[timeline.uuid] = ordinal
      by_ordinal[ordinal] = timeline
    end
  end
  maps
end

private def reference_versions(database : DB::Database) : Array({Int64, String})
  versions = [] of {Int64, String}
  database.query("SELECT history_key, version FROM history_versions") do |result_set|
    result_set.each { versions << {result_set.read(Int64), result_set.read(String)} }
  end
  versions
end

if reference_path = ENV["DELTA_DB_REFERENCE_DATABASE"]?
  describe "populated Delta database differential" do
    it "decodes and canonically re-encodes every persisted history version" do
      database = DB.open("sqlite3://#{reference_path}?mode=ro")
      begin
        maps = reference_actor_maps(database)
        versions = reference_versions(database)
        versions.empty?.should be_false

        versions.each do |history_key, text|
          by_uuid, by_ordinal = maps.fetch(history_key)
          version = DeltaDB::HistoryVersion.decode_version_text(text, by_ordinal)
          version.encode_version_text(by_uuid).should eq text
        end
      ensure
        database.close
      end
    end
  end
else
  pending "populated Delta database differential; set DELTA_DB_REFERENCE_DATABASE" do
  end
end
