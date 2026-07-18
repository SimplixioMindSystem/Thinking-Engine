# Embedded semantic memory

SimpliXio uses an offline-first semantic index on iOS and macOS. Normal capture,
indexing, and search do not require an account, network connection, or backend.

## Runtime design

This is SimpliXio's native ToucanDB runtime. It preserves ToucanDB's persistent
vector-search contract but uses Apple frameworks instead of bundling the Python,
NumPy, SciPy, PyTorch, or FAISS distribution into the application.

- `OfflineStore` is the device-local source of truth and cache for notes. When a
  server is configured, server snapshots are reconciled into it without deleting
  captures that are still queued for upload.
- `SemanticMemoryStore` is a rebuildable derived index.
- Apple's built-in `NLEmbedding` provides the sentence vectors; the runtime reads
  and persists the actual model revision and dimension instead of hard-coding it.
- Vectors are normalized once at write time and stored as `Float32` SQLite BLOBs.
- SQLite uses WAL journaling and `NORMAL` synchronization to avoid rewriting the
  complete index for each note.
- The derived database is protected with iOS file protection, excluded from device
  backups, and uses a bounded WAL so a rebuildable cache does not waste backup or
  storage capacity.
- Search loads compatible vectors into one contiguous row-major matrix and uses
  Accelerate for a single matrix-vector multiplication.
- A bounded min-heap selects top-K results in `O(N log K)` without sorting the
  entire corpus.
- Reciprocal-rank fusion combines semantic results with deterministic lexical
  results without assuming that their raw scores share a scale.
- The model identifier, revision, and dimension are stored with every vector.
  An OS model change therefore causes safe local re-embedding.

Connected and offline search both use this embedded path. The server remains the
synchronization authority, but normal queries do not incur network latency or send
search text off-device. Server-created, updated, and deleted notes update the
durable local cache immediately and enqueue ordered semantic-index maintenance. A
complete server refresh removes stale server records while preserving pending
local captures.

Source-note persistence precedes derived-index scheduling. Index maintenance runs
at utility priority, and operations are serialized so an older update cannot race
a newer deletion. Initial backfill commits batches of 64 records on macOS or 24 on
iOS, yields every eight notes for interactive actor responsiveness, stops when
cancelled, thermally constrained, or when iOS Low Power Mode is active, and resumes
from SHA-256 content hashes on the next launch. Search never waits for a full
backfill: it uses the currently indexed records plus lexical results immediately.

Both note-search surfaces use a 250 ms cancellable debounce. SwiftUI cancels the
superseded task as the query changes, and the engine also uses request generations
so an older network or local result cannot overwrite a newer query. The iOS Review
notes segment and the macOS Notes workbench share the same search path.

Settings exposes index availability, compatible record count, model dimension,
local storage size, and a manual rebuild action on both platforms.

## Privacy and data flow

Search queries and Apple-generated embedding vectors remain on-device. Source
records, profile fields, and explicit relevance feedback may be sent to the
configured server for synchronization and personalization. Leave the Server URL
empty to keep the workflow local-only.

The iOS/macOS and watchOS executables bundle valid `PrivacyInfo.xcprivacy`
manifests. They disclose the applicable synced data types, declare no tracking,
and document the approved reasons for app-local `UserDefaults` and semantic-index
file metadata. Keep these manifests aligned with the product's actual data flow
and App Store Connect privacy answers whenever sync behavior changes.

## Backend decision

A backend is optional:

- **No backend:** private, offline semantic search for data stored on one device.
- **Optional backend:** account sync, collaboration, server-side ingestion, or a
  corpus too large to keep on the device.

Synchronize source records rather than Apple-generated vectors. Each device can
rebuild its vectors using the locally available embedding revision. A server may
use ToucanDB with a different embedding model because remote results are returned
as ranked record IDs, not mixed directly into the local vector space.

## Scale policy

Use exact Accelerate search while profiling shows it meets the latency and memory
budget. The automated suite validates correctness and records cold and warm timings
over 10,000 synthetic 512-dimensional `Float32` vectors without presenting a
development-machine measurement as an iPhone guarantee. Real embedding generation
is deliberately incremental and excluded from the interactive search path.

The warm-search regression bound runs on every test. A stable performance runner
can additionally enforce the cold-load budget with
`SIMPLIXIO_ENFORCE_COLD_SEARCH_BUDGET=1 swift test`; sanitizer and shared CI hosts
should record the cold timing without applying that hardware-sensitive threshold.

Benchmark the oldest supported iPhone before release. Consider a native
approximate-nearest-neighbor index only when measured device data shows the exact
scan no longer meets the product latency target, generally at much larger personal
corpora. Keep Python, PyTorch, and FAISS out of the application bundle.

The watch target retains lexical search and conditionally compiles out the
embedding, SQLite, and Accelerate implementation. This avoids unnecessary CPU,
storage, binary linkage, and battery use on the watch.
