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
