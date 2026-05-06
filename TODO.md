# TODO

## Enable coverage for e2e tests

`make coverage` instruments only the unit tests (`cheat_manager_test.nim`).
The e2e tests spawn a debug binary that is not coverage-instrumented, so
state-machine branches exercised by e2e tests are not reflected in the report.

To fix: add a `make coverage-e2e` target that builds a separate
coverage-instrumented binary (with `--passC:--coverage --passL:--coverage
--lineDir:on`) and sets `BINARY` to that path when running
`cheat_manager_e2e.nim`. The gcda files will land in the same `nimcache/`
directory and can be merged with the unit-test gcda before running gcovr.
