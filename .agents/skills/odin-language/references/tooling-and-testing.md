# Odin Tooling and Testing

## Contents

- Compiler commands
- Checks and vetting
- Tests
- Test runner options
- Build flags and compile-time config
- Installation/version notes

## Compiler Commands

Common commands:

```sh
odin check .
odin build .
odin run .
odin test .
```

Package paths are directories. To run one standalone file as its own package:

```sh
odin run path/to/file.odin -file
```

Use existing project tasks first. If a repo has `mise test`, `just test`, `make`, CI scripts, or wrapper scripts, prefer them because they may pass required flags, targets, or environment variables.

## Checks and Vetting

Useful strict flags, depending on project policy:

```sh
odin check . -vet
odin check . -vet -strict-style -vet-tabs -warnings-as-errors
```

The official examples repository expects contributions to compile with:

```sh
-vet -strict-style -vet-tabs -disallow-do -warnings-as-errors
```

Do not force those flags on every project unless it already follows them or the user asks. They are useful for local validation when tightening style.

## Tests

Odin tests are ordinary procs marked with `@(test)` and usually accept `t: ^testing.T`.

```odin
package tests

import "core:testing"

@(test)
my_test :: proc(t: ^testing.T) {
    testing.expect_value(t, 2 + 2, 4)
}
```

Run tests in a package:

```sh
odin test .
```

Run tests in imported packages below a test aggregator:

```sh
odin test tests/ -all-packages
```

Important behavior:

- The runner can run tests concurrently.
- The runner tracks memory by default.
- Each test thread has custom allocator state, reducing cross-test leak fallout.
- `defer` is usually enough for cleanup, but it will not run if a thread panics.
- Use `testing.cleanup` only for rare cleanup that must happen after panic/timeout, and keep cleanup procedures extremely defensive.

Useful `core:testing` API:

- `testing.expect(t, condition, message?)`
- `testing.expectf(t, condition, format, args...)`
- `testing.expect_value(t, actual, expected)`
- `testing.set_fail_timeout(t, duration)`
- `testing.fail(t)`
- `testing.fail_now(t)`
- `t.seed` for deterministic random reset within a run.

## Test Runner Options

Test runner options are `#config` values passed with `-define:`.

```sh
odin test . -define:ODIN_TEST_SHORT_LOGS=true
odin test . -define:ODIN_TEST_RANDOM_SEED=12345
odin test . -define:ODIN_TEST_NAMES=package.test_name
```

Useful options:

- `ODIN_TEST_THREADS=<n>`: set worker thread count; `0` means available cores.
- `ODIN_TEST_TRACK_MEMORY=false`: disable memory tracking.
- `ODIN_TEST_ALWAYS_REPORT_MEMORY=true`: report memory for all cases.
- `ODIN_TEST_THREAD_MEMORY=<bytes>`: initial memory per thread.
- `ODIN_TEST_NAMES=<package.test_name,test_name,...>`: select tests by name.
- `ODIN_TEST_FANCY=false`: disable animated colored progress.
- `ODIN_TEST_CLIPBOARD=true`: copy failed test names when supported.
- `ODIN_TEST_PROGRESS_WIDTH=<n>`: control progress width.
- `ODIN_TEST_RANDOM_SEED=<n>`: reproduce random-dependent failures.
- `ODIN_TEST_LOG_LEVEL=<debug|info|warning|error|fatal>`: filter logs.
- `ODIN_TEST_SHORT_LOGS=true`: shorter log output.

## Build Flags and Compile-Time Config

Common patterns:

```sh
odin build . -out:bin/app
odin run . -debug
odin check . -target:linux_amd64
odin test . -define:MY_OPTION=true
```

In code:

```odin
Use_Fast_Path :: #config(USE_FAST_PATH, true)

when ODIN_OS == .Darwin {
    // platform code
}
```

Build tags and feature directives appear at file top:

```odin
#+build linux || darwin
#+feature dynamic-literals
```

Respect existing project build tags. A file gated for one platform may be intentionally invisible on another target.

## Installation/Version Notes

Official install docs list releases, nightly builds, source builds, and third-party package managers. The compiler supports host builds on major desktop/server OSes and can target more platforms.

Practical version rules:

- Odin evolves. If syntax or packages fail unexpectedly, check `odin version`, project docs, and official docs.
- The compiler executable expects to be next to `base`, `core`, and `vendor`, unless `ODIN_ROOT` points elsewhere.
- macOS builds may require Xcode command-line tools and LLVM/lld for some targets.
- Windows uses the MSVC toolchain and Windows SDK.
- Linux/Unix builds use Clang/LLVM.
