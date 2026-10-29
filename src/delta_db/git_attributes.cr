# src/delta_db/git_attributes.cr
module DeltaDB
  enum EolConfig
    Lf
    Crlf
    Native
    Auto
  end

  module GitAttributes
    def self.parse_config_bool(value : String) : Bool?
      case value.downcase
      when "", "false", "no", "off", "0", "0.0" then false
      when "true", "yes", "on", "1", "1.0"      then true
      else                                           nil
      end
    end
  end
end
