# src/delta_db/worktree/git_attributes.cr
module DeltaDB
  class Worktree
    module GitAttributes
      enum EolConfig
        Lf
        Crlf
        Native
        Auto
      end

      def self.parse_config_bool(value : String) : Bool?
        case value.downcase
        when "", "false", "no", "off", "0", "0.0" then false
        when "true", "yes", "on", "1", "1.0"      then true
        else                                           nil
        end
      end
    end
  end
end
