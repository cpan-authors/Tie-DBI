# CLAUDE.md — Tie-DBI

## What this is

Tie::DBI and Tie::RDBM — Perl modules that tie hashes to relational databases via DBI.
Tie::DBI maps each row to a sub-hash of fields (via Tie::DBI::Record). Tie::RDBM maps
each row to a single scalar value (with optional Storable freeze/thaw).

Legacy CPAN module, first released 1998. Maintained by Todd Rinaldo.

## Project structure

```
lib/Tie/DBI.pm    # Main module + Tie::DBI::Record (same file)
lib/Tie/RDBM.pm   # Simpler key-value variant
t/DBI.t            # Tests for Tie::DBI (SQLite by default)
t/RDBM.t           # Tests for Tie::RDBM (SQLite by default)
Makefile.PL        # ExtUtils::MakeMaker build
```

## Running tests

```bash
prove -l t/          # Run all tests with local lib/
prove -l t/DBI.t     # Just DBI tests
prove -l t/RDBM.t    # Just RDBM tests
```

Tests auto-detect the best available DBD driver (prefer SQLite). To force a specific driver:

```bash
DRIVER=SQLite prove -l t/
```

Always use `prove -l` (or `prove -Ilib`) to pick up local changes instead of system-installed modules.

## Code conventions

- **Perl 5.8 minimum** (`use 5.008`). No features beyond that baseline.
- **perltidy** is configured via `.perltidyrc` (4-space indent, 400-char line limit).
- **No version bumps** in PRs. Version changes happen at release time only.
- **No release prep** (MANIFEST updates, Changes entries) in feature/fix PRs.
- Commit messages use conventional commits: `fix:`, `feat:`, `test:`, `docs:`.

## Critical patterns

### DBI/RDBM parity

Tie::DBI and Tie::RDBM solve the same problem with different internals. **Every bug
found in one must be checked in the other.** This has held true across 20+ fix sessions.
The two test files (DBI.t, RDBM.t) should stay in sync when the same behavior is tested.

Key differences:
- DBI.pm uses Tie::DBI::Record (sub-hash per row); RDBM.pm stores scalar values directly
- DBI.pm has dynamic sth scanning in DESTROY; RDBM.pm uses a hardcoded tag list
- DBI.pm has ENCODING support; RDBM.pm does not
- RDBM.pm has freeze/thaw (Storable) support; DBI.pm does not
- RDBM.pm has a `cached_value` optimization for each() loops; DBI.pm does not need one

### Driver capability hashes

Both modules maintain driver-specific capability hashes (`%CAN_BIND`, `%CAN_BINDSELECT`,
`%DOES_IN`, etc. in DBI.pm; `%CAN_BIND`, `%Types` in RDBM.pm). When adding a new driver,
update ALL relevant hashes in BOTH files.

### CASESENSITIV (not a typo)

The option is spelled `CASESENSITIV` (no E). This is the original API and cannot be changed.
When `CASESENSITIV=0` (default), field names from the DB are lowercased in `_fields()`.

### Statement handle caching

Both modules cache prepared statement handles in `$self->{$tag}` via `_prepare()`.
The `_prepare` method either creates a new sth (first call) or reuses the cached one.
DESTROY must clean up all cached sth handles BEFORE disconnecting the dbh, or
SEGV occurs during global destruction.

### _run_query return value

`_run_query` returns the sth on success, `undef` on failure. Callers MUST check
the return value before calling methods on it. Some callers historically missed this.

## Testing patterns

- **Test behavior, not implementation.** Tests validate observable outcomes (return values,
  DB state, warnings), never inspect source code.
- **Two-commit pattern for bug fixes:** first commit adds a failing test that proves the bug
  exists, second commit fixes the code and the test passes.
- **Simulating driver-specific code paths:** Set capability flags on the tied object to test
  paths normally only reached with specific drivers (e.g., `$tied->{CanBindSelect} = 0`
  to test the Oracle fallback path with SQLite).
- **SKIP blocks** for driver-specific tests (e.g., CSV driver lacks proper NULL support).
- **Explicit cleanup** at the end of test files: untie hashes, disconnect dbh, undef handles
  to prevent SEGV during global destruction.

## What NOT to do

- Never bump `$VERSION` in PRs
- Never modify MANIFEST or Changes in feature/fix PRs
- Never add dependencies without discussion
- Never restructure the single-file module layout (DBI.pm contains both Tie::DBI and Tie::DBI::Record)
