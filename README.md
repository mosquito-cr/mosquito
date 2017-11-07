# mosquito

Mosquito is a generic background job runner written specifically for Crystal. Significant inspiration from the Ruby gem Sidekiq.

Mosquito currently provides these features:
- Delayed execution
- Scheduled execution
- Job Storage in Redis
- Crystal hash style `?` methods for parameter getters which return nil instead of raise

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  mosquito:
    github: [your-github-name]/mosquito
```

## Usage

### Step 1: Require Mosquito in your application loader

```crystal
require "mosquito"

# Your jobs folder
require "jobs/*"

# In a second application target, or behind some other switching or multi-fiber interface, run tasks:
Mosquito::Runner.start
```

### Step 2: Define a queued job

```crystal
class PutsJob < Mosquito::QueuedJob
  params(message : String | Nil)

  def perform
    puts message
  end
end
```

### Step 3: Trigger that job

```crystal
PutsJob.new(message: "Hello Background Job World!").enqueue
```

### Success

```
> crystal run src/worker.cr
2017-11-06 17:07:29 -0700 - Mosquito is buzzing...
2017-11-06 17:07:51 -0700 - Queues: puts_job
2017-11-06 17:07:51 -0700 - Running task puts_job<mosquito:task:1510013271686:246> from puts_job
2017-11-06 17:07:51 -0700 - [PutsJob] ohai background job
2017-11-06 17:07:51 -0700 - task puts_job<mosquito:task:1510013271686:246> succeeded, took 0.0 seconds
```

## Contributing

1. Fork it ( https://github.com/[your-github-name]/mosquito/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [[your-github-name]](https://github.com/[your-github-name]) Robert L Carpenter - creator, maintainer
