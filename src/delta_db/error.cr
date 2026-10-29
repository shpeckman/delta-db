# src/delta_db/error.cr
module DeltaDB
  class Error < Exception
  end

  class NotFoundError < Error
  end

  class SealedError < Error
  end

  class MissingBlobError < Error
  end

  class InvariantError < Error
  end
end
