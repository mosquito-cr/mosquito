<img src="logo/logotype_horizontal.svg" alt="mosquito">

[![GitHub](https://img.shields.io/github/license/mosquito-cr/mosquito.svg?style=for-the-badge)](https://tldrlegal.com/license/mit-license)

<img src="https://mosquito-cr.github.io/images/amber-mosquito-small.png" align="right">

Mosquito is a generic background job runner written primarily for Crystal. Significant inspiration from experience with the successes and failings many Ruby gems in this vein. Once compiled, a mosquito binary can start work in about 10 milliseconds.

Mosquito currently provides these features:

- Delayed execution (`SendEmailJob.new(email: :welcome, address: user.email).enqueue(in: 3.minutes)`)
- Scheduled / Periodic execution (`RunEveryHourJob.new`)
- Job Storage in Redis
- Automatic rescheduling of failed jobs
- Progressively increasing delay of rescheduled failed jobs
- Dead letter queue of jobs which have failed too many times
- Rate limited jobs

Current Limitations:
- Visibility into a running job network and queue is limited. There is a working proof of concept [visualization API](https://github.com/mosquito-cr/mosquito/issues/90) and [bare-bones terminal application](https://github.com/mosquito-cr/tui-visualizer).

## Project State

The Mosquito project is stable. A few folks are using Mosquito in production, and it's going okay.

There are some features which would be nice to have, but what is here is both tried and tested.

If you're using Mosquito, please [get in touch](https://github.com/mosquito-cr/mosquito/discussions) on the Discussion board or [on Crystal chat](https://crystal-lang.org/community/) with any questions, feature suggestions, or feedback.

## Installation

Update your `shard.yml` to include mosquito:

```diff
dependencies:
+  mosquito:
+    github: mosquito-cr/mosquito
```

## Usage

### Step 1: Define a queued job

```crystal
# src/jobs/puts_job.cr
class PutsJob < Mosquito::QueuedJob
  param message : String

  def perform
    puts message
  end
end
```

### Step 2: Trigger that job

```crystal
# src/<somewher>/<somefile>.cr
PutsJob.new(message: "ohai background job").enqueue
```

### Step 3: Run your worker to process the job

```crystal
# src/worker.cr

Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]
end

Mosquito::Runner.start
```

```text
crystal run src/worker.cr
```

### Success

```
> crystal run src/worker.cr
2017-11-06 17:07:29 - Mosquito is buzzing...
2017-11-06 17:07:51 - Running task puts_job<...> from puts_job
2017-11-06 17:07:51 - [PutsJob] ohai background job
2017-11-06 17:07:51 - task puts_job<...> succeeded, took 0.0 seconds
```

[More information about queued jobs](https://mosquito-cr.github.io/manual/index.html#queued-jobs) in the manual.

------

## Periodic Jobs

Periodic jobs run according to a predefined period -- once an hour, etc.

This periodic job:
```crystal
class PeriodicallyPutsJob < Mosquito::PeriodicJob
  run_every 1.minute

  def perform
    emotions = %w{happy sad angry optimistic political skeptical epuhoric}
    puts "The time is now #{Time.local} and the wizard is feeling #{emotions.sample}"
  end
end
```

Would produce this output:
```crystal
2017-11-06 17:20:13 - Mosquito is buzzing...
2017-11-06 17:20:13 - Queues: periodically_puts_job
2017-11-06 17:20:13 - Running task periodically_puts_job<...> from periodically_puts_job
2017-11-06 17:20:13 - [PeriodicallyPutsJob] The time is now 2017-11-06 17:20:13 and the wizard is feeling skeptical
2017-11-06 17:20:13 - task periodically_puts_job<...> succeeded, took 0.0 seconds
2017-11-06 17:21:14 - Queues: periodically_puts_job
2017-11-06 17:21:14 - Running task periodically_puts_job<...> from periodically_puts_job
2017-11-06 17:21:14 - [PeriodicallyPutsJob] The time is now 2017-11-06 17:21:14 and the wizard is feeling optimistic
2017-11-06 17:21:14 - task periodically_puts_job<...> succeeded, took 0.0 seconds
2017-11-06 17:22:15 - Queues: periodically_puts_job
2017-11-06 17:22:15 - Running task periodically_puts_job<...> from periodically_puts_job
2017-11-06 17:22:15 - [PeriodicallyPutsJob] The time is now 2017-11-06 17:22:15 and the wizard is feeling political
2017-11-06 17:22:15 - task periodically_puts_job<...> succeeded, took 0.0 seconds
```

[More information on periodic jobs](https://mosquito-cr.github.io/manual/index.html#periodic-jobs) in the manual.

## Advanced usage

For more advanced topics, including [use with Lucky Framework](https://mosquito-cr.github.io/manual/lucky_framework.html), [throttling or rate limiting](https://mosquito-cr.github.io/manual/rate_limiting.html), check out the [full manual](https://mosquito-cr.github.io/manual).

## Contributing

Contributions are welcome. Please fork the repository, commit changes on a branch, and then open a pull request.

### Crystal Versions

Mosquito aims to be compatible with the latest Crystal release, and the [latest patch for all post-1.0 minor crystal versions](https://github.com/mosquito-cr/mosquito/blob/master/.github/workflows/ci.yml#L17).

For development purposes [you're encouraged to stay in sync with `.tool-versions`](https://github.com/mosquito-cr/mosquito/blob/master/.tool-versions).

### Testing

This repository uses [minitest](https://github.com/ysbaddaden/minitest.cr) for testing. As a result, `crystal spec` doesn't do anything helpful. Do this instead:

```
make test
```

In lieu of `crystal spec` bells and whistles, Minitest provides a nice alternative to [running one test at a time instead of the whole suite](https://github.com/ysbaddaden/minitest.cr/pull/31).
