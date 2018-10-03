
<img src="logo/logotype_horizontal.svg" alt="mosquito">

[![CircleCI](https://img.shields.io/circleci/project/github/robacarp/mosquito/master.svg?logo=circleci&label=Circle%20CI&style=for-the-badge)](https://circleci.com/gh/robacarp/mosquito)
[![Crystal Version](https://img.shields.io/badge/crystal-0.26-blue.svg?longCache=true&style=for-the-badge)](https://crystal-lang.org/)
[![GitHub](https://img.shields.io/github/license/robacarp/mosquito.svg?style=for-the-badge)](https://tldrlegal.com/license/mit-license)


Mosquito is a generic background job runner written specifically for Crystal. Significant inspiration from my experience with the successes and failings of the Ruby gem Sidekiq.

Mosquito currently provides these features:
- Delayed execution
- Scheduled / Periodic execution
- Job Storage in Redis
- Crystal hash style `?` methods for parameter getters which return nil instead of raise
- Automatic rescheduling of failed jobs
- Progressively increasing delay of failed jobs
- Dead letter queue of jobs which have failed too many times

Current Limitations:
- Job failure delay, maximum retry count, and several other variables cannot be easily configured.
- Visibility into the job queue is difficult and must be done through redis manually.

![](https://cdn.shopify.com/s/files/1/0242/0179/products/amber1_1024x1024.png?v=1455409061)

## Project State

Updated 2018-10-01

> Sufficient working beta.
>
> Use in a production environment at your own risk, and please open issues and feature requests.

## Installation

Update your `shard.yml` to include mosquito:

```diff
dependencies:
+  mosquito:
+    github: robacarp/mosquito
```

Further installation instructions are available for use with Amber as well as a vanilla crystal application:

- [Installing with Amber](https://github.com/robacarp/mosquito/wiki/Usage:-Amber)
- [Adding to a vanilla crystal application](https://github.com/robacarp/mosquito/wiki/Usage:-vanilla-crystal)

## Usage

### Step 1: Define a queued job

```crystal
class PutsJob < Mosquito::QueuedJob
  params message : String

  def perform
    puts message
  end
end
```

### Step 2: Trigger that job

```crystal
PutsJob.new(message: "ohai background job").enqueue
```

### Step 3: Run your worker to process the job

```text
crystal run bin/worker.cr
```

### Success

```
> crystal run src/worker.cr
2017-11-06 17:07:29 - Mosquito is buzzing...
2017-11-06 17:07:51 - Running task puts_job<...> from puts_job
2017-11-06 17:07:51 - [PutsJob] ohai background job
2017-11-06 17:07:51 - task puts_job<...> succeeded, took 0.0 seconds
```

[More information about queued jobs](https://github.com/robacarp/mosquito/wiki/Queued-jobs) in the wiki.

------

## Periodic Jobs

Periodic jobs run according to a predefined period. 

This periodic job:
```crystal
class PeriodicallyPutsJob < Mosquito::PeriodicJob
  run_every 1.minute

  def perform
    emotions = %w{happy sad angry optimistic political skeptical epuhoric}
    puts "The time is now #{Time.now} and the wizard is feeling #{emotions.sample}"
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

More information: [periodic jobs on the wiki](https://github.com/robacarp/mosquito/wiki/Periodic-Jobs)

## Connecting to Redis

Mosquito currently reads directly from the `REDIS_URL` environment variable to connect to redis. If no variable is set, it uses redis connection defaults to connect to redis on localhost. 

## Contributing

Contributions are welcome. Please fork the repository, commit changes on a branch, and then open a pull request.

### Testing

This repository uses [minitest](https://github.com/ysbaddaden/minitest.cr) for testing. As a result, `crystal spec` doesn't do anything helpful. Do this instead:

```
make test
```

In lieu of `crystal spec` bells and whistles, Minitest provides a nice alternative to [running one test at a time instead of the whole suite](https://github.com/ysbaddaden/minitest.cr/pull/31).

## Contributors

- [robacarp](https://github.com/robacarp) robacarp - creator, maintainer
