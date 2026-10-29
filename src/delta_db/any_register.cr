# src/delta_db/any_register.cr
module DeltaDB
  struct AnyRegister(T)
    getter value : T

    def initialize(@value : T)
    end
  end
end
