# On-device semantic search

SimpliXio uses an offline-first semantic index on iOS and macOS. Normal capture,
indexing, and search do not require an account, network connection, or backend.

## Runtime design

This is SimpliXio's native semantic-search implementation. It uses Apple
frameworks instead of bundling Python, NumPy, SciPy, PyTorch, or FAISS into the
application.

- `OfflineStore` is the device-local source of truth for notes, profile context,
  decisions, insights, and feedback.
- `ICloudSyncService` compresses the private source-state payload, encrypts it
  on-device with AES-GCM, and syncs only authenticated ciphertext through the
  user's iCloud account. The 256-bit key is a synchronizable iCloud Keychain
  item shared only by signed SimpliXio targets. Per-record timestamps and
  deletion tombstones keep edits deterministic and prevent deleted notes from
  reappearing.
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

All Apple-app search uses this embedded path. Queries do not incur network latency
or send search text off-device. Source changes update the durable local store
first and enqueue ordered semantic-index maintenance. iCloud synchronizes source
records, never device-specific embedding vectors.

Source-note persistence precedes derived-index scheduling. Index maintenance runs
at utility priority, and operations are serialized so an older update cannot race
a newer deletion. Initial backfill commits batches of 64 records on macOS or 24 on
iOS, yields every eight notes for interactive actor responsiveness, stops when
cancelled, thermally constrained, or when iOS Low Power Mode is active, and resumes
from SHA-256 content hashes on the next launch. Search never waits for a full
backfill: it uses the currently indexed records plus lexical results immediately.

Both note-search surfaces use a 250 ms cancellable debounce. SwiftUI cancels the
superseded task as the query changes, and the engine also uses request generations
so an older local result cannot overwrite a newer query. The iOS Review
notes segment and the macOS Notes workbench share the same search path.

Settings keeps private-search status simple and offers a recovery action when a
fresh local index is needed.

## Privacy and data flow

Search queries and Apple-generated embedding vectors remain on-device. When the
user enables private sync, source records, profile fields, decisions, insights,
and explicit relevance feedback synchronize through the user's iCloud account.
Readable source state never enters iCloud key-value storage: encryption happens
first, and a delayed or unavailable key leaves changes safely on the device
instead of overwriting cloud state.
The Apple app targets exclude the optional API client and upload queue, and the
macOS app has no general network-client entitlement.

The iOS/macOS and watchOS executables bundle valid `PrivacyInfo.xcprivacy`
manifests. They declare no developer collection or tracking and document the
approved reasons for app-local `UserDefaults` and semantic-index file metadata.
Keep these manifests aligned with the product's actual data flow and App Store
Connect privacy answers whenever sync behavior changes.

## Service boundary

The Apple apps do not require a product backend:

- **On-device:** capture, ranking, search, Weekly Review, Decision Replay, and
  public-safe newsletter drafting.
- **Private iCloud:** source-state synchronization between iPhone, Mac, and Apple
  Watch using AES-GCM ciphertext and an iCloud Keychain key, with a local-only
  fallback when iCloud or its private key is unavailable.
- **Optional Python tooling:** public-safe demos, integrations, and approved
  automation outside the shipping Apple apps.

Synchronize source records rather than Apple-generated vectors. Each device can
rebuild its local index using the embedding revision available on that device.

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

The current encrypted sync envelope is intentionally bounded below iCloud
key-value storage's 1 MB quota. When a personal corpus no longer fits, SimpliXio
keeps the complete local copy and reports that private sync needs attention; it
does not truncate or silently discard captures. A future migration to encrypted
CloudKit records can raise this ceiling without changing the local source of
truth.
