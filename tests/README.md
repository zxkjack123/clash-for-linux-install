# Tests

Lightweight test suite for `clash-for-linux-install` shell scripts.

## Running

```bash
bash tests/run_tests.sh
```

All tests are self-contained — no network access or running mihomo required.

## Structure

- `run_tests.sh` — Test runner (pure bash, no external deps). Provides `assert_eq`, `assert_contains`, `assert_not_contains`.
- `test_*.sh` — Test files. Each defines `test_*` functions that are auto-discovered and executed.
- `testdata/` — Static YAML configs used by tests.

## Writing tests

1. Create `tests/test_<module>.sh`
2. Define functions prefixed with `test_`
3. Use `assert_eq`, `assert_contains`, `assert_not_contains` (provided by `run_tests.sh`)
4. The runner sources your file and calls each `test_*` function automatically
