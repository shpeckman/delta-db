require "./delta_db/point"
require "./delta_db/point_utf16"
require "./delta_db/offset_utf16"
require "./delta_db/unclipped"
require "./delta_db/text_summary"
require "./delta_db/chunk"
require "./delta_db/rope"
require "./delta_db/eol"
require "./delta_db/clock"
require "./delta_db/delta"
require "./delta_db/storage"
require "./delta_db/anchor"
require "./delta_db/diff"
require "./delta_db/locator"
require "./delta_db/buffer"
require "./delta_db/patch"
require "./delta_db/operation_queue"
require "./delta_db/network"
require "./delta_db/history"

# DeltaDB is a Crystal port of Delta's `deltadb` crate (itself a re-consolidation
# of Zed's `rope`/`text`/`sum_tree` crates plus a Delta-original history engine).
#
# This file is the text-model slice (Phase 1): the rope chunk + summary primitives
# that every other layer builds on.
module DeltaDB
  VERSION = "0.1.0"
end
