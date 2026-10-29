# src/delta_db/seal_state.cr
module DeltaDB
  class SealState
    getter history_version : History::Version? = nil
    getter global_version : VersionVector? = nil

    def sealed? : Bool
      !@history_version.nil? || !@global_version.nil?
    end

    def seal(version : History::Version) : Nil
      return if @history_version == version
      ensure_mutable!
      @history_version = version
    end

    def seal(version : VersionVector) : Nil
      return if @global_version == version
      ensure_mutable!
      @global_version = version
    end

    def ensure_mutable! : Nil
      raise SealedError.new("object is sealed") if sealed?
    end
  end
end
