### 2018-01-16

- Use configurable Logger instead of writing directly to stdout
- Job classes can now disable rescheduling on failure
- Log output is now colorized and formatted to be read by human eyes
- BUG: task id was mutating on each save, causing weird logging when tasks reschedule.

### 2017-12

- PERFORMANCE: adding IDLE_WAIT to prevent slamming redis when the queues are empty. Smarter querying of the queues for work.
