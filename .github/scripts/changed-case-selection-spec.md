# Changed Case Selection Spec

## Background

The CI function test flow currently receives a PR change list in `docs_changed.txt`.
When a PR only changes:

- `test/cases/**`
- `test/ci/cases.task`

the goal is to avoid running unrelated function cases.

This spec defines the selection rules used by:

- `prepare_test_env.py`
- `test_runner.py`

## Goal

When the PR only modifies case files and/or the case list file, only run the cases that are still relevant after the PR changes.

Relevant means:

- cases explicitly added or re-enabled in `cases.task`
- changed case files that still have an active entry in `cases.task`

Everything else must be skipped.

## Inputs

### File Change List

Produced by `prepare_test_env.py`:

- `tmp/<pr>_<run>_<attempt>/docs_changed.txt`

Rules:

- contains non-doc, non-markdown changed files
- path separator is normalized to `/`

### Case List Diff

Produced by `prepare_test_env.py`:

- `tmp/<pr>_<run>_<attempt>/cases_task_diff.txt`

Rules:

- generated from `git diff --unified=0 <merge-base> FETCH_HEAD -- test/ci/cases.task`
- used only to discover active added lines in `cases.task`
- deleted lines are informative only and must not be executed

### Active Case Lists

Current repository files after PR checkout:

- `community/test/ci/cases.task`
- `community/test/ci/win_cases.task`

Only active lines are executable:

- non-empty
- not starting with `#`

## Cases-Only Mode Entry Condition

Changed-case selection mode is enabled only if every changed file is one of:

- `test/cases/**`
- `test/ci/cases.task`

If any other file is changed, the system falls back to the original function-test behavior.

## Selection Rules

### Rule 1: Deleted Or Commented-Out Task Lines Must Not Run

If `git diff` shows a line deleted from `cases.task`, that line must not be executed.

This includes cases where the line was effectively disabled by being commented out.

Implication:

- deleted lines are not used as a fallback source for execution
- a changed case file is ignored if its active task entry no longer exists in current `cases.task`

### Rule 2: Added Or Uncommented Active Task Lines Must Run

If `git diff` contains an added active line in `cases.task`, that case becomes runnable.

Examples:

- newly added case line
- previously commented case line that is now active again

Implication:

- added active lines contribute to the selected case set even if the underlying case file itself was not modified

### Rule 3: Changed Case Files Run Only If Still Active In Current `cases.task`

If a file under `test/cases/**` changed, it is selected only if the current active `cases.task` still contains an entry for that case.

If the changed case cannot be found in active `cases.task`, it must be skipped and logged.

Implication:

- code changes to a case file do not force execution by themselves
- the current active task list is the source of truth

### Rule 4: Only `cases.task` Comment/Removal Changes Mean Skip

If the PR only changes `cases.task`, and after applying the rules above there are no active selected cases, then `run_function_test` must be skipped.

Typical examples:

- only commenting out one line
- only deleting one line
- only reordering comments without adding active lines

### Rule 5: Mixed Changes Outside Cases Scope Use Original Logic

If the PR changes any file outside:

- `test/cases/**`
- `test/ci/cases.task`

then no changed-case filtering is applied.

## Platform Rules

### Linux

Linux uses a generated temporary task file:

- `community/test/ci/temp_run_cases.task`

If the selected Linux case list is empty, Linux function test is skipped.

### Windows

Windows maps the selected case paths onto active entries in:

- `community/test/ci/win_cases.task`

and writes:

- `community/test/ci/temp_run_win_cases.task`

If no selected case exists in active `win_cases.task`, Windows function test is skipped.

### macOS

macOS logic is unchanged.

macOS still uses the existing fixed case list and does not attempt full `cases.task` driven selection.

## Logging Requirements

The runner should print clear reasons for non-execution.

Expected messages include:

- changed cases not present in active `cases.task`
- selected cases not present in active `win_cases.task`
- only comment/removal changes detected, so function test is skipped

## Implementation Mapping

### `prepare_test_env.py`

Responsibilities:

- generate `docs_changed.txt`
- generate `cases_task_diff.txt`
- do this in the shared local preparation flow

Current implementation location:

- `output_file_no_doc_change`

### `test_runner.py`

Responsibilities:

- detect whether the PR is in cases-only mode
- parse active task lines
- parse added lines from `cases_task_diff.txt`
- build selected case set
- filter Linux and Windows task files
- skip execution when no active selected cases remain

Current implementation locations:

- `_extract_case_path_from_task_line`
- `_read_cases_task_diff`
- `_resolve_task_lines_for_cases`
- `_get_case_selection`
- `run_function_test`

## Canonical Scenarios

### Scenario A

Change:

- modify `test/cases/x.py`
- comment out or delete the corresponding line in `cases.task`

Expected result:

- do not run that case
- print that the changed case is not present in active `cases.task`
- if no other selected case remains, skip function test

### Scenario B

Change:

- only comment out or delete a line in `cases.task`

Expected result:

- skip function test

### Scenario C

Change:

- add an active case line to `cases.task`

Expected result:

- run exactly that added case

### Scenario D

Change:

- modify `test/cases/x.py`
- leave its active entry in `cases.task`

Expected result:

- run exactly that changed case

### Scenario E

Change:

- modify `test/cases/x.py`
- also modify files outside cases scope

Expected result:

- do not enter changed-case filtering mode
- use original function-test behavior

## Non-Goals

- changing macOS fixed-case strategy
- altering legacy workflows outside the shared Python script path
- executing deleted task lines for backward compatibility

## Future Modification Guidance

Any future change to this behavior should preserve these invariants unless explicitly revised:

- deleted or commented-out `cases.task` entries never run
- active added or uncommented entries can run
- changed case files only run when still present in active `cases.task`
- only cases-scope changes should trigger filtering mode