# Changelog

## 0.2.1
### 2018-10-01
- Logo contributed by @psikoz
- Add several more automated tests
- Add configuration for CI : `make test demo` will run all acceptance criteria
- Add demo section
- Release version 0.2.1

### 2018-08-16
- Update to specify crystal 0.26
- Add several tests
- Add makefile

## 0.2.0
### 2018-06-22
- Update to specify crystal-redis 2.0 and crystal 0.25
- Release version 0.2.0

## 0.1.1
### 2018-06-08
- Breaking: Update Mosquito::Model type alias to match updates to Granite
- Misc typo fixes and flexibility upgrades
- Update Crystal specification 0.23.1 -> .24.2
- Correctly specify and sync version numbers from shard.yml / version.cr / git tag
- Release version 0.1.1

### 2018-01-16
- Use configurable Logger instead of writing directly to stdout
- Job classes can now disable rescheduling on failure
- Log output is now colorized and formatted to be read by human eyes
- BUG: task id was mutating on each save, causing weird logging when tasks reschedule.

### 2017-12
- PERFORMANCE: adding IDLE_WAIT to prevent slamming redis when the queues are empty. Smarter querying of the queues for work.
