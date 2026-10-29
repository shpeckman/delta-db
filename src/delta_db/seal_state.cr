# src/delta_db/seal_state.cr
module DeltaDB
  class SealState
    getter history_version : HistoryVersion? = nil
    getter global_version : Global? = nil

    def sealed? : Bool
      !@history_version.nil? || !@global_version.nil?
    end

    def seal(version : HistoryVersion) : Nil
      return if @history_version == version
      ensure_mutable!
      @history_version = version
    end

    def seal(version : Global) : Nil
      return if @global_version == version
      ensure_mutable!
      @global_version = version
    end

    def ensure_mutable! : Nil
      raise SealedError.new("object is sealed") if sealed?
    end
  end
end
