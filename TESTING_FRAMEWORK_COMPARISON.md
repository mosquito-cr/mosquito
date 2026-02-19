# Minitest vs Crystal Spec: Migration Analysis

## Background

Mosquito uses `ysbaddaden/minitest.cr` (~> 1.6.0) for its test suite. The Crystal
ecosystem has shifted significantly since this choice was made. The built-in `Spec`
module (accessed via `require "spec"` and the `crystal spec` command) is now the
overwhelmingly standard choice. This document evaluates whether rewriting the test
suite is worth it, what risks exist, and how different the two syntaxes actually are.

---

## 1. Is rewriting worth it?

**Arguments for migrating:**

- **Minitest is a niche dependency.** The Crystal community has converged on the
  stdlib Spec. The vast majority of shards, Crystal's own standard library tests,
  and all official documentation use `crystal spec`. Contributors to mosquito will
  expect stdlib Spec and may be confused by minitest idioms.

- **Minitest is in maintenance mode.** The last tagged release was v1.3.0 in
  December 2023. The repository has 0 open issues, which signals stability but
  also indicates minimal active development. The author (ysbaddaden) is still
  active in the Crystal ecosystem (contributing to threading/sync work), but
  minitest itself isn't receiving new features.

- **Tooling friction.** `crystal spec` is a first-class compiler command. It
  integrates with IDE tooling, CI templates, and the `shards` workflow out of
  the box. Minitest requires `minitest/autorun` and won't run via the standard
  `crystal spec` command without workarounds. This is a papercut for every new
  contributor.

- **One fewer dependency.** Removing minitest from `shard.yml` simplifies the
  dependency tree. The stdlib Spec is always available and version-matched to the
  compiler.

**Arguments against migrating (or for deferring):**

- **It works.** The existing test suite is functional, passing, and well-organized.
  A rewrite is effort spent not building features or fixing bugs.

- **The test suite is moderately large.** ~2,800 lines across 40 spec files with
  a nontrivial helper layer. This is not a trivial find-and-replace.

- **Risk of subtle behavioral changes.** Test lifecycle, ordering, and failure
  reporting differ between the two frameworks. A migration could mask regressions
  if not done carefully.

**Verdict:** The migration is worth doing, but it isn't urgent. The strongest
argument is contributor experience: every Crystal developer expects `crystal spec`
to just work, and every minitest idiom is a speed bump. The dependency reduction
and tooling alignment are real but secondary benefits. Timing-wise, this is a good
candidate for a dedicated cleanup effort rather than something to interleave with
feature work.

---

## 2. Strategies to reduce migration risk

### a. Migrate mechanically, not creatively

The rewrite should be a syntax translation, not a test improvement effort.
Resist the urge to refactor test logic, rename things, restructure files, or
"fix" tests while migrating. Each spec file should be translatable in isolation,
and the diff should be reviewable as "same test, different syntax."

### b. Migrate one directory at a time

Both frameworks can coexist in the same project during migration. You could
migrate `spec/mosquito/backend/` first, verify it passes, merge, then move on
to `spec/mosquito/runners/`, etc. This keeps PRs small and reviewable.

Coexistence approach:
- Minitest specs keep `require "minitest/autorun"` via `spec_helper.cr`
- Migrated specs use `require "spec"` via a new or modified helper
- Both can run, though they'll need to be invoked separately during the
  transition

### c. Migrate helpers last (or keep them as-is)

The custom helpers (`clean_slate`, `assert_logs_match`, `assert_message_received`,
`eavesdrop`) are the highest-risk part of the migration. They're defined as methods
on `Minitest::Test` and use minitest's `assert`/`refute` internally. These should
be migrated last, after all the spec files are converted, so you can see the full
picture of what the helpers actually need to provide.

In Crystal spec, custom matchers don't exist as a first-class concept. The helpers
would become either:
- Top-level methods that raise `Spec::AssertionFailed` on failure
- Methods that return values you then call `.should` on

### d. Ensure the test suite is green before starting

Run the full suite, confirm everything passes, and tag that commit. This gives
you a known-good baseline to diff against.

### e. Use the compiler as a safety net

Crystal's type system will catch most mechanical errors (wrong method names,
missing requires, type mismatches). If the migrated code compiles and the tests
pass, you have high confidence the translation is correct.

---

## 3. Syntax comparison

### What's identical

The structural DSL is essentially the same:

```crystal
# Minitest                          # Crystal Spec
describe Foo do                     describe Foo do
  describe "feature" do               describe "feature" do
    it "does a thing" do                it "does a thing" do
      # ...                               # ...
    end                                 end
  end                                 end
end                                 end
```

`describe`, `it`, and nesting all work identically. `context` is available in
Crystal spec as an alias for `describe` (minitest doesn't have `context`).

### What changes: assertions -> expectations

This is the core of the migration. Minitest uses `assert_*`/`refute_*` functions.
Crystal spec uses `value.should matcher` / `value.should_not matcher`.

Here's how every assertion used in the mosquito test suite maps:

| Minitest (current)                          | Crystal Spec equivalent                     | Count |
|---------------------------------------------|---------------------------------------------|-------|
| `assert condition`                          | `condition.should be_truthy`                | 56    |
| `refute condition`                          | `condition.should be_falsey`                | (incl)|
| `assert_equal expected, actual`             | `actual.should eq expected`                 | 190   |
| `refute_equal expected, actual`             | `actual.should_not eq expected`             | (few) |
| `assert_nil value`                          | `value.should be_nil`                       | 11    |
| `refute_nil value`                          | `value.should_not be_nil`                   | (incl)|
| `assert_includes collection, element`       | `collection.should contain element`         | 14    |
| `refute_includes collection, element`       | `collection.should_not contain element`     | 3     |
| `assert_instance_of Klass, obj`             | `obj.should be_a Klass`                     | 6     |
| `assert_same a, b`                          | `a.should be b`                             | 1     |
| `assert_empty collection`                   | `collection.empty?.should be_true`          | 5     |
| `assert_raises(Ex) { }`                     | `expect_raises(Ex) { }`                     | 2     |
| `assert_in_epsilon(exp, act)`               | `actual.should be_close(expected, delta)`   | 2     |

Note the argument order flip: minitest is `assert_equal expected, actual`, while
Crystal spec is `actual.should eq expected`. This is the most common source of
copy-paste errors during migration.

### What changes: setup/teardown

| Minitest                  | Crystal Spec              |
|---------------------------|---------------------------|
| `before { }`             | `before_each { }`         |
| `after { }`              | `after_each { }`          |
| (no equivalent)           | `before_all { }`          |
| (no equivalent)           | `after_all { }`           |

### What has no direct equivalent: `getter`/`let`

This is the biggest syntactic gap. Minitest provides `let` and (via Crystal's
stdlib) `getter` macros for lazy-initialized per-test instance variables:

```crystal
# Minitest - used 35 times across the test suite
getter(job) { PassingJob.new }
getter(queue) { Mosquito::Queue.new(name) }

# Also used - 28 times
let(queued_test_job) { QueuedTestJob.new }
```

Crystal spec has **no `let` equivalent.** The options are:

1. **Local variables in `describe` blocks** - works for simple values but not
   for objects that need per-test isolation:
   ```crystal
   describe Foo do
     job = PassingJob.new  # shared across all `it` blocks - usually wrong
   end
   ```

2. **`before_each` with instance-like variables** - Crystal spec doesn't support
   instance variables in the same way since specs aren't classes. You'd need a
   workaround pattern.

3. **Inline construction** - just create the object in each `it` block:
   ```crystal
   it "does something" do
     job = PassingJob.new
     job.run
     job.should be_truthy
   end
   ```

4. **Helper methods at the top level or in a module** - define a method that
   returns a fresh instance.

For mosquito's test suite, option 3 (inline construction) is probably the right
default. The `getter` pattern is used for convenience, not because the tests
actually need memoization. In the cases where setup is more complex (like the
coordinator and executor specs), `before_each` with a local variable or a small
helper method works.

### What has no direct equivalent: custom assertion helpers

The test suite defines 44 uses of `assert_logs_match`/`refute_logs_match` and
14 uses of `assert_message_received`. In Crystal spec, these would become
either:

```crystal
# Option A: helper that returns a bool, used with should
logs_match("pattern").should be_true

# Option B: custom expectation (more idiomatic but more work)
logs.should match_log("pattern")

# Option C: just inline it
log_entries.any? { |e| e.message =~ /pattern/ }.should be_true
```

### What has no direct equivalent: `clean_slate`

`clean_slate` is used 88 times. It's a block that flushes the backend, clears
logs, and clears PubSub messages. In Crystal spec, this maps naturally to
`before_each`/`after_each`:

```crystal
before_each do
  Mosquito.backend.flush
  TestingLogBackend.instance.clear
  PubSub.instance.clear
end
```

This is actually cleaner than the current approach since it wouldn't require
wrapping every test body in a block.

### What changes: focus and autorun

| Minitest                          | Crystal Spec                      |
|-----------------------------------|-----------------------------------|
| `require "minitest/focus"`        | built-in                          |
| `require "minitest/autorun"`      | not needed (`crystal spec` just works) |
| `focus` on a test                 | `focus: true` tag on `it`/`describe` |

### Summary of semantic distance

The two frameworks are **moderately different syntactically but semantically
very close**. The test structure (`describe`/`it`) is identical. The main work
is:

1. **Assertion translation** (~290 assertion calls) - mechanical but tedious,
   with the argument-order flip on `assert_equal` being the main pitfall.
2. **`getter`/`let` removal** (~63 usages) - requires thinking about what the
   right replacement is for each case.
3. **Helper rewrite** (~146 helper usages) - `clean_slate` can become
   `before_each`; log/pubsub assertions need small rewrites.
4. **Boilerplate cleanup** - removing minitest requires, `Minitest::Test`
   references, and `autorun`.

None of these changes are conceptually difficult. The risk is proportional to
the number of touch points, not the complexity of any individual change.
