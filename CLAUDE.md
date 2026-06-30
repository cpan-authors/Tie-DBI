# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Tie-DBI is a CPAN distribution providing two `tie`-based modules that map Perl
hashes onto SQL tables via DBI:

- **`Tie::DBI`** (`lib/Tie/DBI.pm`, v1.09) — ties a hash to an *existing* table.
  One column is the hash key; each row becomes a tied sub-hash of field/value
  pairs. Never creates or alters schema.
- **`Tie::RDBM`** (`lib/Tie/RDBM.pm`, v0.74) — a simpler key/value store backed
  by a two-or-three-column table (key, value, optional `frozen` flag). With
  Storable installed it can freeze/thaw arbitrary Perl references into a binary
  value column. Can create/drop its own table.

The two modules are independent (no shared code) but share the same design
patterns and the GH #7 SEGV fix.

## Commands

```sh
perl Makefile.PL        # generate the Makefile (run after editing Makefile.PL)
make                    # build into blib/
make test               # run the full test suite
make disttest           # build a dist tarball and test it in isolation (CI runs this)
prove -lv t/DBI.t       # run a single test file with lib/ in @INC
perltidy lib/Tie/DBI.pm # reformat per .perltidyrc (note -l=400, very wide lines)
```

Install dependencies with `cpm install --cpanfile cpanfile` (CI uses
`perl-actions/install-with-cpm`). Runtime requires only `DBI`; tests also need
`DBD::SQLite`, `Test::More`, `Test::Pod`, and `Test::Pod::Coverage`.

## Testing notes

- Tests auto-select a DBD driver from those installed (preference order ending
  in SQLite, see the `%DRIVERS` map in each `.t`). **SQLite is the default and
  effectively the only driver CI exercises** — it's the one PREREQ DBD.
- Override the target database with env vars: `DRIVER`, `DB`, `HOST`, `USER`,
  `PASS`, or a full `DBI_DSN`. With none set and a driver present, tests run
  against an in-memory/file SQLite `test` database.
- `t/DBI.t` and `t/RDBM.t` `plan` a fixed test count; if you add or remove
  assertions you must update the `plan tests => N` line.
- CI (`.github/workflows/testsuite.yml`) runs with `AUTHOR_TESTING`,
  `AUTOMATED_TESTING`, and `RELEASE_TESTING` all set to 1 across Linux (every
  Perl ≥ 5.8 via `perldocker/perl-tester`), macOS, and Windows.

## Architecture and gotchas

### Driver capability tables drive all SQL generation
Both modules branch on hard-coded per-driver capability hashes near the top of
the file. In `Tie::DBI` these are `%CAN_BIND`, `%CAN_BINDSELECT`,
`%CANNOT_LISTFIELDS`, `%BROKEN_INSERT`, `%NO_QUOTE`, and `%DOES_IN`; `TIEHASH`
copies the relevant flags into per-object fields (`CanBind`, `CanBindSelect`,
etc.). **When adding support for a new DBD driver, add it to the appropriate
hashes** — behavior is determined entirely by these tables, not by probing the
driver.

### Quote-vs-bind is the central correctness concern
`_run_query` either uses DBI placeholders (`?` + `execute(@bind)`) or manually
substitutes quoted values into the SQL string, depending on driver flags. The
subtle invariant: callers (FETCH/EXISTS/DELETE/`_update`/`_insert`) pre-quote
key/values *only when `!CanBind`*, while `_run_query` re-quotes *only when
`CanBind` but the query is a WHERE on a non-`CanBindSelect` driver* (the Oracle
path). Get this split wrong and you produce double-quoted SQL. See the
`CanBindSelect=0` regression test at the bottom of `t/DBI.t`.

### DESTROY ordering prevents SEGV (GH #7)
During global destruction DBI children are freed in undefined order; if the
`dbh` is freed before a cached statement handle, the sth's destructor calls
`sqlite3_finalize` on a stale handle and segfaults. Both `DESTROY` methods
therefore explicitly `finish` and `delete` every cached sth *before*
disconnecting the dbh, and disconnect only when `needs_disconnect` is set (i.e.
the module opened the connection — never disconnect a caller-supplied dbh).
Two related traps codified in comments:
- Do **not** write `my $sth = EXPR unless COND;` — the `my` in a statement
  modifier is undefined behavior and leaks the handle (see `_fields`).
- The explicit-cleanup blocks at the end of the `.t` files (undef-ing tied
  values and untie-ing) exist for this same reason; keep them.

### Statement handle caching
`_prepare` caches prepared statement handles in `$self->{$tag}` keyed by a tag
string (e.g. `"fetch1"`, `"insert@fields"`, `"fetchkeys"`). Reused handles get
`finish`-ed before re-execution. `each()`-style iteration relies on the cached
`fetchkeys` handle persisting across FIRSTKEY/NEXTKEY; both modules `delete` it
to work around a Sybase bug when iteration ends.

### Tie::DBI::Record
A second package in `Tie/DBI.pm`. `FETCH` on the outer hash returns a hashref
tied to `Tie::DBI::Record`, so per-field reads/writes (`$h{row}{col}`) route
back through the parent's `_fetch_field`/`STORE`. This is the source of the
documented performance penalty (multiple round-trips per field op).

### Multi-key FETCH magic
`$h{$a,$b}` (keys joined by `$;`) triggers a single `IN (...)` / `OR` query and
returns an arrayref — distinct from a normal array slice. `FETCH` splits on
`$;` to detect this.

## Conventions

- Formatting is enforced by `.perltidyrc` (4-space indent, `-l=400` line
  length, `-bar` opening braces). Run `perltidy` before committing style-
  sensitive changes; use `# tidyoff` / `# tidyon` to fence regions.
- POD lives inline at the bottom of each module and is the canonical user docs;
  `README.md` is generated from `Tie::DBI`'s POD — edit the POD, not the README.
  `Test::Pod::Coverage` runs in CI, so new public subs need documentation.
- Bump `$VERSION` in the changed module and add a `Changes` entry for releases.
