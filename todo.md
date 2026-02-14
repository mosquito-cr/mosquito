# Backend Refactor Plan

## Why

The `Backend` abstract class conflates two concerns: **database interaction** (store, retrieve, get, set, lock, publish, etc.) and **named queue operations** (enqueue, dequeue, schedule, etc.). Database interaction is implemented as class methods via `ClassMethods` module + `macro inherited`, while queue operations are instance methods on named Backend instances. `Mosquito.backend` returns a CLASS, storage ops can't hold instance state, and instance delegation methods exist just to forward to `self.class.*`.

This refactor is foundational work that enables:
1. **Relational DB backend** — SQL needs completely different queue implementations (INSERT/UPDATE on tables vs LPUSH/LMOVE on Redis lists). Queue ops must be backend-specific, which is why they live in `Backend::Queue`.
2. **Redis connection pooling** — Backend must be instance-based to hold a pool reference. `Backend::Queue` can also hold connection-level state (checked-out connections, transactions).

## New Architecture

```
Backend (abstract, instance-based)
├── Storage: store, retrieve, get, set, delete, increment, expires_in
├── Global: list_queues, list_overseers, register_overseer, flush
├── Coordination: lock?, unlock, publish, subscribe
├── Metrics: average, average_push
├── Key building: build_key (concrete, uses KeyBuilder + config)
└── Factory: queue(name) → Backend::Queue

Backend::Queue (abstract, holds @backend + @name)
├── Queue ops: enqueue, dequeue, schedule, deschedule, finish, terminate
├── Inspection: size, dump_*_q, *_size, scheduled_job_run_time
├── Key construction: waiting_q, scheduled_q, pending_q, dead_q
└── Delegations: store, retrieve, delete, expires_in, build_key → @backend

RedisBackend < Backend
├── @connection : Redis::Client? (lazy, was @@connection)
└── RedisBackend::Queue < Backend::Queue

TestBackend < Backend
└── TestBackend::Queue < Backend::Queue
```

`Mosquito.backend` returns a `Backend` instance (lazily initialized in Configuration).

## Implementation Checklist

### Core files

- [x] **`src/mosquito/backend.cr`** — Remove `ClassMethods` module, `macro inherited`, `named()`. All former ClassMethods become abstract instance methods. Add `Backend::Queue` nested abstract class with queue ops, `*_q` key methods, and convenience delegations (store, retrieve, delete, expires_in, build_key → @backend). Add `queue(name)` factory + `_build_queue` protected abstract.

- [x] **`src/mosquito/redis_backend.cr`** — `@@connection` → `@connection`. All `self.*` → instance methods. Lua script executors → instance methods. Extract `RedisBackend::Queue < Backend::Queue` with all queue instance methods. `_build_queue` returns `Queue.new(self, name)`.

- [x] **`src/mosquito/test_backend.cr`** — All `self.*` → instance methods. Extract `TestBackend::Queue < Backend::Queue` with stubs. `EnqueuedJob` struct and `@@enqueued_jobs` stay on TestBackend class level.

- [x] **`src/mosquito/configuration.cr`** — `property backend : Backend.class = RedisBackend` → lazy `@backend : Backend?` with getter defaulting to `RedisBackend.new` and a setter.

### Source callers — `Backend.build_key` → `Mosquito.backend.build_key` (4 files)

- [x] `src/mosquito/runners/coordinator.cr:12`
- [x] `src/mosquito/periodic_job_run.cr:5`
- [x] `src/mosquito/api/executor.cr:45`
- [x] `src/mosquito/api/overseer.cr:49`

### Source callers — `.named()` → `.queue()` + type `Backend` → `Backend::Queue`

- [x] `src/mosquito/queue.cr:80,88`
- [x] `src/mosquito/api/queue.cr:8,16`

### Other source

- [x] `src/ye_olde_redis.cr` — Monkeypatch targets `RedisBackend::Queue#dequeue`

### Zero-change callers (verify only)

These call `Mosquito.backend.store/get/set/etc` — same API, now instance methods:
`metadata.cr`, `job_run.cr`, `api/executor.cr`, `runners/coordinator.cr`, `api/overseer.cr`, `api.cr`, `runners/queue_list.cr`, `api/observability/publisher.cr`, `api/job_run.cr`, `rate_limiter.cr`, `job.cr`

### Spec changes

- [x] `spec/helpers/global_helpers.cr:17` — return type `Backend.class` → `Backend`
- [x] `spec/mosquito/backend_spec.cr:18,22` — `.named` → `.queue`
- [x] `spec/mosquito/backend/queueing_spec.cr:5` — type `Backend` → `Backend::Queue`, `.named` → `.queue`
- [x] `spec/mosquito/backend/deleting_spec.cr:6` — type `Backend` → `Backend::Queue`, `.named` → `.queue`
- [x] `spec/mosquito/backend/inspection_spec.cr:5` — type `Backend` → `Backend::Queue`, `.named` → `.queue`
- [x] `spec/mosquito/queue_spec.cr:15` — type `Backend` → `Backend::Queue`, `.named` → `.queue`
- [x] `spec/mosquito/queue_spec.cr:45` — `backend.class.list_queues` → `Mosquito.backend.list_queues`
- [x] `spec/mosquito/job_run/storage_spec.cr:4` — type + `.named` → `.queue`
- [x] `spec/mosquito/testing_backend_spec.cr:9,16,23,30` — `backend: Mosquito::TestBackend` → `backend: Mosquito::TestBackend.new`

## Verification

```sh
shards build                # compile check
crystal spec spec/          # full test suite
make demo                   # integration check
```
