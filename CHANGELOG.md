# Changelog

The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Mosquito::Api now allows for inspecting the state of the state of a mosquito cluster. Many of these features are disabled by default by the configuration property `config.publish_metrics`.
    - Executor api implemented in #147
    - JobRun api implemented in #148 and #161
    - Overseer api implemented in #150
    - Queue api implemented in #153
- Mosquito now publishes a variety of events and metrics to a redis pubsub channel. This behavior is disabled by default with the configuration property `config.publish_metrics`.
    - Executor events in #154: job-started and job-finished
    - Overseer events in #160: starting, executor-created, executor-died, stopping, and stopped
    - Queue events: enqueue, dequeue, reschedule, forget, and banish
    - Expected job duration is now published with executor events
  The Mosquito API can be used to subscribe to these events with `Mosquito::API.event_receiver`
- Pluggable dequeue adapters allow customizing how jobs are selected from queues
    - `DequeueAdapter` abstract base class defines the adapter interface
    - `ShuffleDequeueAdapter` is the default, preserving existing randomized behavior
    - `WeightedDequeueAdapter` allows queue-level prioritization via configurable weights
    - Configurable via `Mosquito.configure { |c| c.dequeue_adapter = ... }`
- Executor count is now configurable (default increased from 3 to 6)
    - Set via `Mosquito.configure { |c| c.executor_count = 10 }`
    - Override with the `MOSQUITO_EXECUTOR_COUNT` environment variable
- `JobRun#started_at` and `JobRun#finished_at` timestamps are now exposed as typed `Time?` getters
- Graceful worker shutdown: on SIGTERM/SIGINT the overseer stops dequeuing, waits for in-flight executors to finish, and requeues any jobs left in pending back to waiting
- Overseers now take ownership of job runs when dequeued, and clean up abandoned pending job runs on startup

### Changed
- (minor breaking) `Configuration#connection_string` has been renamed to `Configuration#backend_connection_string` and `Configuration#backend_connection` to clarify that these delegate to the backend instance.
- (minor breaking) Logs are now emitted from runners with a slighly different source tag. (#152)
  For example:
  The overseer boot message used to be:
    `INFO - mosquito.runners.overseer.4315742080: Overseer<4315742080> is starting`
  Now the message is simply:
    `INFO - mosquito.overseer: starting`
- Mosquito now runs CI checks for compatibility with Crystal 1.6
- The coordinator now uses UTC time instead of monotonic time

### Fixed
- the queue_list runner was never being shut down, but it is now as of (#165)
- Fixed a bug which would cause a mosquito server to hang at exit indefinitely if a job was mid-run during an interrupt. (#165)
- Fixed a bug which would cause a correctly exiting server to prematurely exit without emitting shutdown sequence logs and events. (#165)
- Crashed executors are now properly detected and replaced, preventing overseers from running with no executors
- Overseer now correctly deregisters on clean exit
- Pubsub logging now uses the `mosquito.events` namespace instead of the root `mosquito` namespace
- Queue `@empty` latch no longer permanently prevents re-dequeue after a queue drains
- Observer functionality is correctly gated behind the `publish_metrics` config flag
- Executor events are correctly scoped to within the overseer
- Fixed a latent bug which caused job duration to be reported incorrectly
- Fixed `Mosquito::Api.list_queues`

### Performance
- Optimized `metadata#set` to decrease the number of redis commands

## [2.0.0]
### Added
- Adds a test backend, which can be used to inspect jobs that were enqueued and
  the parameters they were enqueued with.
- Job#fail now takes an optional `retry` parameter which defaults to true, allowing
  a developer to explicitly mark a job as not retry-able during a job run. Additionally
  a `should_retry` property exists which can be set as well.
- Mosquito::Configuration now provides `global_prefix` to change the global Redis namespace 
  prefix, allowing for more than one mosquito app to share a redis instance (thanks @dammer, cf #134).

### Fixed
- PeriodicJobs are now correctly run once per interval in an environment with many workers.
- Running more than ~10 workers no longer causes workers to crash, fixing #137 (cf #138).
- Mosquito is now more broadly compatible with jgaskins redis, swapping 0.7.0 for 0.7, and
  forward compatible through 0.8. (thanks @rmarronnier)
- Mosquito now more gracefully responds to SIGTERM, fixes #122, cf #123.
- High CPU usage on linux is no longer an issue, fixes #126, cf #128.

### Breaking Changes
- The QueuedJob `params` macro has been replaced with `param`
  which declares only one parameter at a time.
- JobRun#delete now explicitly takes an Int, rather than simply defaulting to 0 (thanks @jwoertink, cf #136).
- removes deprecated Backend.delete(String, Int32), use Backend.delete(String, Int64) instead.
- removes deprecated Queue#length, use Queue#size instead.
- removes option to run the cron scheduler declaratively, it is now always on with a distributed lock.

### Performance
- Dramatically decreases the time spent listing queues #120
- Replaces #keys with #scan_each to list runners #138
- Provides for multiple executors operating under a single runner #123


## [1.0.2]
### Fixed
- Mosquito::Runner.start now captures the thread with a spin lock again. The new
  behavior of returning imediately can be achieved by calling #start(spin: false)   

## [1.0.1] [YANKED]
### Added
- Implements a distributed lock for scheduler coordination. The behavior is opt-in
  for now, but will become the default in the next release. See #108.
- Provides a helpful error message for most implementation errors dealing with
  declaring params.

### Changed
- Mosquito::QueuedJob: the `params` macro has been deprecated in favor of `param`.
  See #110.
- The deprecated Redis command [`rpoplpush`](https://redis.io/commands/rpoplpush/)
  is no longer used. This lifts the minimum redis server requirement up to 6.2.0
  and jgaskins redis to > 0.7.0.
- Mosquito::Runner.start no longer captures the thread with a spin lock. [DEFECT]

### Removed
- Mosquito config option `run_cron_scheduler` is no longer present, multiple
  workers will compete for a distributed lock instead. See #108.

## [1.0.0]
### Added
- Jobs can now specify their retry/reschedule logic with the #rescheduleable?
  and #reschedule_interval methods.
- Job metadata storage engine.
- Jobs can now specify `after` hooks.
- Mosquito::Runner now has a `stop` method which halts the runner after
  completion of any running tasks. See issue #21 and pull #87.
- Mosquito config option `run_cron_scheduler` is no longer present, multiple
  workers will compete for a distributed lock instead.

### Changed
- The storage backend is now implemented via interface, allowing alternate
  backends to be implemented.
- The rate limiting functionality is now implemented in a module,
  `Mosquito::RateLimiter`. See pull #77 for migration details.
- ** BREAKING ** `Job.job_type` has been replaced with `Job.queue_name`. The
  functionailty is identical but easier to access. See #86.
- `log` statements now properly identify where they're coming from rather than
  just 'mosquito'. See issue #78 and pull #88.
- Mosquito now connects to Redis using a connection pool. See #89
- ** BREAKING **  `Mosquito.settings` is now `Mosquito.configuration`. While
  this is technically a public API, it's unlikely anyone is using it for
  anything.
- Mosquito::Runner.start need not be called from a spawn, it will spawn on it's own.

### Removed
- Runner.idle_wait configuration is deprecated. Instead use
  Mosquito.configure#idle_wait.
- Built in serializer for Granite models, and the Model type alias. See
  Serializers in the documentation if the functionality is necessary.
- Mosquito no longer depends on luckyframework/habitat.

### Fixed
- Boolean false can now be specified as the default value for a parameter:
  `params(name = false)`

## [0.11.2] - 2022-01-25
### Fixed
- #66 Jobs with no parameters can now be enqueued without specifying an empty
  `params()`.
- #65 PeriodicJobs can now specify their run period in months.

### Notes
The v0 major version is now bugfix-only. Please update to v1.0. v0 will be
supported as long as it's feasible to do so.

## [0.11.1] - 2022-01-17
### Added
- Jobs can now specify `before` hooks, which can abort before the perform is
  triggered.
- The Cron scheduler for periodic jobs can now be disabled via
  Mosquito.configure#run_cron_scheduler
- The list of queues which are watched by the runner can now be configured via
  Mosquito.configure#run_from.

### Updated
- Redis shard 2.8.0, removes hash shims which are no longer needed. Thanks
  @jwoertink.

## [0.11.0] - 2021-04-10
Proforma release for Crystal 1.0.

## [0.10.0] - 2021-02-15
### Added
- UUID serializer helpers.

### Updated
- Switches from Benchmark.measure to Time.measure, thanks @anapsix.
- Runner.idle_wait is now configured via Mosquito.configure instead of directly
  on Mosquito::Runner.

## [0.9.0] - 2020-10-26
### Added
- Allows redis connection string to be specified via config option, thanks
  @watzon.

### Deprecated
- Connecting to redis via implicit REDIS_URL parameter is deprecated, thanks
  @watzon.

## [0.8.0] - 2020-05-28
### Fixed
- (Breaking) Dead tasks which have failed and expired are now cleaned up with a
  Redis TTL. See Pull #48.

## [0.7.0] - 2020-05-05
### Added
- ability to configure Runner.idle_wait period, thanks @mamantoha.

### Updated
- Point to Crystal 0.34.0, thanks @alex-lairan.

### Changed
- Replaces `Logger` with the more flexible `Log`.

## [0.6.0] - 2019-12-19
### Updated
- Point to Crystal 0.31.1, 0.32.1.
- Redis version, thanks @nsuchy.

## [0.5.0] - 2019-06-14
### Fixed
- Issue #26 Unresolved local var error, thanks @blacksmoke16.

## [0.4.0] - 2019-04-26
### Added
- Throttling logic, thanks @blacksmoke16.

## [0.3.0] - 2018-11-25
### Updated
- Point to crystal 0.27, thanks @blacksmoke16.

### Fixed
- Brittle/intermittently failing tests.

## [0.2.1] - 2018-10-01

### Added
- Logo, contributed by @psikoz.
- configuration for CI : `make test demo` will run all acceptance criteria.
- demo section.
- makefile.

### Updated
- specify crystal 0.26.
- simplify macro logic in QueuedJob.

## [0.2.0] - 2018-06-22
### Updated
- Specify crystal-redis 2.0 and crystal 0.25.

## [0.1.1] - 2018-06-08

### Added
- Job classes can now disable rescheduling on failure.

### Updated
- Readme.
- Misc typo fixes and flexibility upgrades.
- Update Crystal specification 0.23.1 -> .24.2.
- Correctly specify and sync version numbers from shard.yml / version.cr / git
  tag.
- Use configurable Logger instead of writing directly to stdout.
- Log output is now colorized and formatted to be read by human eyes.

### Changed
- Breaking: Update Mosquito::Model type alias to match updates to Granite.

### Fixed
- BUG: task id was mutating on each save, causing weird logging when tasks
  reschedule.
- PERFORMANCE: adding IDLE_WAIT to prevent slamming redis when the queues are
  empty. Smarter querying of the queues for work.
