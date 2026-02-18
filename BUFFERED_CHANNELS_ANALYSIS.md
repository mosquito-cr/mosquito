# Buffered Channels Analysis for Mosquito

## Current Channel Inventory

All four channels in the codebase are unbuffered (`Channel(T).new`):

| Channel | Type | Location | Purpose |
|---------|------|----------|---------|
| `idle_notifier` | `Channel(Bool)` | `src/mosquito/runners/overseer.cr:44` | Executors signal idle state to overseer |
| `work_handout` | `Channel(Tuple(JobRun, Queue))` | `src/mosquito/runners/overseer.cr:49` | Overseer distributes jobs to executors |
| `notifier` | `Channel(Bool)` | `src/mosquito/runnable.cr:159` | Shutdown completion notification |
| `stream` | `Channel(Backend::BroadcastMessage)` | `src/mosquito/redis_backend.cr:188` | Redis pub/sub event delivery |

## Channel-by-Channel Analysis

### 1. `idle_notifier` — Would benefit from buffering

**Current behavior:** When an executor becomes idle, it spawns a new fiber just to send `true` on this channel (`executor.cr:47`). The overseer receives from it inside a `select` with a timeout (`overseer.cr:128-133`). If the overseer is busy (e.g., in the middle of a Redis dequeue), the spawned fiber blocks until the overseer is ready to receive.

**Problem:** Multiple executors can finish jobs nearly simultaneously. Because the channel is unbuffered, only one idle signal can be in-flight at a time. The second and third executor idle signals block in their spawned fibers until the overseer loops back around to receive again. Meanwhile, those executors are actually idle and available but the overseer doesn't know yet — it may timeout and skip dequeuing.

Additionally, when no jobs are available the overseer re-sends the idle signal to itself in a spawned fiber (`overseer.cr:153`). This is a workaround for the unbuffered channel consuming the signal even when no work was dispatched.

**With `Channel(Bool).new(executor_count)`:**
- All idle signals arrive without blocking the executor fibers.
- No need to spawn a fiber just to avoid deadlocking on the send.
- The overseer can drain multiple idle signals per loop iteration, dispatching multiple jobs in a single pass.
- The self-re-send workaround on line 153 could be simplified or eliminated since the signal wouldn't be consumed unless work is actually dispatched.

### 2. `work_handout` — Marginal benefit, but has a case

**Current behavior:** The overseer sends a job tuple only after confirming an executor is idle (`overseer.cr:144`). The executor receives with `receive?` which returns nil if the channel is closed (`executor.cr:73`).

**Why unbuffered mostly works:** The overseer's logic ensures it only sends when an executor is idle, so the send rarely blocks for long. The protocol is essentially: idle signal received → dequeue from Redis → send on work_handout → executor picks it up.

**With `Channel(Tuple(JobRun, Queue)).new(executor_count)`:**
- The overseer could pre-fetch jobs and fill the buffer during idle moments, reducing latency between an executor finishing one job and receiving the next.
- In high-throughput scenarios, this could reduce the round-trip through the overseer loop per job.
- However, this would require reworking the idle-notification protocol since the overseer currently dequeues only one job per loop iteration by design.

### 3. `notifier` (shutdown) — No benefit

**Current behavior:** Created in `stop`, used exactly once: a monitoring fiber sends `true`/`false` when shutdown completes (`runnable.cr:159-171`). The caller blocks on `receive` to wait for shutdown.

**Why buffered is unnecessary:** This is a one-shot synchronization primitive. There's exactly one sender and one receiver, and both sides expect to block. A buffered channel would change nothing observable.

### 4. `stream` (Redis pub/sub) — Would benefit from buffering

**Current behavior:** Redis subscription callbacks send messages into the channel (`redis_backend.cr:196`). The consumer (the API layer) receives from it. If the consumer is slow, the Redis subscription fiber blocks on the send, which causes Redis pub/sub message backpressure inside the Crystal process.

**Problem:** Redis pub/sub delivers messages asynchronously. If the consumer briefly stalls (e.g., processing a previous message), the subscription fiber is blocked and subsequent messages queue in the Redis client library instead of in Crystal's channel. This is less controllable and can lead to unexpected disconnections if the subscription connection backs up.

**With `Channel(Backend::BroadcastMessage).new(buffer_size)`:**
- Absorbs short bursts of pub/sub messages without blocking the subscription fiber.
- Gives the consumer time to catch up without risking Redis connection issues.
- Makes the backpressure behavior explicit and configurable.

## Summary

| Channel | Benefit from Buffering | Suggested Capacity |
|---------|----------------------|-------------------|
| `idle_notifier` | **High** | `executor_count` (default 3) |
| `work_handout` | Low-to-moderate | `executor_count` if pre-fetching is added |
| `notifier` | None | Keep unbuffered |
| `stream` | **Moderate-to-high** | Configurable (e.g., 32 or 64) |

## Drawbacks

1. **Increased memory usage** — Each buffered slot holds a copy of the channel's type in memory. For `Bool` this is negligible. For `Tuple(JobRun, Queue)` or `BroadcastMessage` it's still small but nonzero.

2. **Masking backpressure** — Buffered channels absorb bursts but can hide sustained overload. If the system is consistently producing faster than it consumes, a buffer just delays the problem. Monitoring buffer fill levels becomes important.

3. **Subtle behavioral changes** — The current code uses `spawn` to wrap sends specifically *because* the channels are unbuffered. With buffered channels, some of these spawns become unnecessary and should be removed to avoid spawning fibers that complete instantly (minor overhead, but also code that misleads future readers about intent).

4. **Harder to reason about ordering** — Unbuffered channels provide a strong synchronization guarantee: the sender and receiver rendezvous. With buffered channels, the sender can race ahead, which makes it harder to reason about the exact state of the system at any point. For the `idle_notifier` specifically, the overseer might see stale idle signals from executors that have since picked up work through another path.

5. **Shutdown complexity** — Buffered channels may still contain unprocessed messages when `close` is called. The current shutdown sequence (`overseer.cr:89`) closes `work_handout` and expects executors to see `nil` from `receive?`. With a buffered channel, executors would drain remaining buffered jobs before seeing the close, which is probably desirable but changes shutdown timing.

## Recommendation

The highest-value change is buffering `idle_notifier` to `executor_count`. This eliminates the spawned-fiber workaround, removes a source of unnecessary latency, and simplifies the idle re-notification logic on `overseer.cr:153`. The `stream` channel for Redis pub/sub is the second priority — it's a classic producer-consumer boundary where buffering improves resilience.
