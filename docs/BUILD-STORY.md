# How Pi Harness was built

Sources: the private development repository's git history (10 commits,
2026-05-04 to 2026-10-27, including one unmerged branch), its one pull
request, and the code in this repository. This public repository is a
one-commit snapshot of that history's `main` branch.

## The problem

AI code review from a single model was not a usable gate. One model's
review would invent issues, miss others, and come back in a different shape
every run, so nothing could read the answer and decide pass or fail. The
goal was a tool that sends the same change to several models from different
providers, gives each one a narrow job, and reduces everything to one exit
code.

## Timeline

| Date | What happened |
|------|---------------|
| 2026-05-04 | `pi-tools v2.0` committed as one 1,895-line change: three entry scripts, four sourced libraries, five persona prompts, an installer. The commit message records that the harness was put through a 12-round self-review cycle (it reviewed its own code) before this commit. Earlier versions are not in the history. |
| 2026-05-04 | Pull request #1 (`fix/pi-grades-omp-patterns`), merged the same day: the grader recognised P0-P3 headings and `SEVERITY:` labels, but omp's reviewer writes emoji severity markers and phrases such as "PASS - No security findings". On a real run all eight reviews graded PARTIAL because no signal was detected. The fix added 35 lines of patterns to `pi-grades`. |
| 2026-05-04 | A second dogfood pass: `pi-swarm` was run against its own codebase and every finding fixed (macOS awk compatibility, Markdown list markers in the P0 regex, unbalanced code fences, cleanup killing only the reviewer PID rather than its process group, infrastructure failures annotating instead of overriding real grades, `--help` on all three scripts). This commit sits on a side branch that was never merged into `main`, so it is **not** in this snapshot. |
| 2026-07 to 2026-10 | Repository housekeeping only (agent instruction files, search index settings, a secret-scanner change, removal of a retired runtime reference in the installer). No changes to the review or grading logic. |

## Key design decisions

- **Bash, sourced libraries.** The harness glues together CLIs that already
  exist (Pi, omp, git). Four sourced files keep each concern (provider
  detection, input capture and cleanup, engine routing, grading) small and
  separately readable, and nothing needs installing beyond the agents
  themselves.
- **Two engines behind one interface.** omp has a built-in reviewer prompt
  with structured P0-P3 output, so it is preferred and the persona is
  appended as a focus. Pi is the fallback, with standalone persona prompts
  that force a `SEVERITY:` line so the grader still has something to match.
- **Grade on explicit signals, treat silence as unsure.** The grader never
  promotes free text to "verified". Blocking signals win over clean ones in
  the same output, negations ("No P0 regressions") are filtered out, and
  fenced code blocks are stripped first so example text inside a review
  cannot change its grade.
- **Swap the model order in `pi-verify`.** The verifier runs on a different
  model family from the one most likely to have written the code, so a
  model is not checking its own work.
- **Isolate every reviewer.** Each parallel reviewer gets its own agent
  directory because the agents keep state in SQLite and parallel instances
  otherwise contend for the same lock.
- **Never send secrets to a model.** `--files` mode skips symlinks, files
  outside the working directory, binaries and secret-looking names before
  anything leaves the machine.

## How AI was used

The code was written with Claude (the commits carry a Claude co-author
line). Review was the harness itself: the 12-round self-review before v2.0,
then two same-day dogfood passes against real model output. That loop is
the point of the tool, and it is also how its two main defects were found:
the grader's blind spot for emoji markers, and the portability and cleanup
problems in the second pass.

## Testing

There is no automated test suite. Verification so far has been running the
harness on real diffs, including its own code, and checking the grades by
hand. The grader is pure text-in, grade-out, which makes it the natural
first target for a table-driven test.

## What did not work

- Matching only the formats the author expected. The first live run graded
  every review PARTIAL because omp's real output used markers the patterns
  did not cover.
- Killing the process group on cleanup, which could take down the parent
  shell; the side-branch fix kills single PIDs instead.

## Current state

v2.0 on `main`, unchanged in its review and grading logic since 2026-05-04.
The second round of dogfood fixes (including `--help`) is written but
unmerged.
