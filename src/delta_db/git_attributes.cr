module DeltaDB
  # Line-ending configuration from `.gitattributes` (the `eol` attribute).
  #
  # Recovered from `deltadb::git_attributes::EolConfig`.
  enum EolConfig
    Lf
    Crlf
    Native
    Auto
  end

  # Parsing helpers for git configuration / attributes.
  #
  # Port of `deltadb::git_attributes` (`parse_config_bool`).
  module GitAttributes
    # Parse a git config boolean: empty/false/no/off/0 -> false,
    # true/yes/on/1 -> true, anything else -> nil.
    def self.parse_config_bool(value : String) : Bool?
      case value.downcase
      when "", "false", "no", "off", "0", "0.0" then false
      when "true", "yes", "on", "1", "1.0"      then true
      else                                           nil
      end
    end
  end
end
