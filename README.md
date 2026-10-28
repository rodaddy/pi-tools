# Pi Harness

Cross-model AI code review: several reviewer personas run on models from
different providers in parallel, and their answers are graded into one
pass/fail verdict.

![Licence: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/licence-PolyForm%20Noncommercial%201.0.0-blue)
![Language: Bash](https://img.shields.io/badge/language-Bash-4EAA25)

![Pi Harness: one diff, many reviewers, one verdict](docs/images/hero.jpg)

## What it is

Pi Harness takes a diff (staged changes, a branch, or any `git diff`
command) or a set of whole files, and sends it to specialised reviewer
personas on two or more LLMs at once. Each review is graded on a five-tier
scale, and the run ends with a single verdict and exit code, so a developer
or a CI step gets one answer instead of eight walls of text.

Three entry points:

- `pi-review` runs one persona against two models.
- `pi-swarm` runs every persona against every model (4 personas x 2 models
  = 8 reviews by default; `--quick` runs 2 x 2; `--files` reviews whole
  files instead of a diff; `--branch` reviews the branch against the
  default branch).
- `pi-verify` checks that code matches a stated intent, with the model
  order swapped so the verifier is a different model family from the one
  that likely wrote the code.

## Why it exists

A single AI reviewer is unreliable. It invents issues, misses real bugs and
answers in a different format every time. No one model catches everything,
and "looks good to me" in free text is not a gate anyone can trust.

The harness answers that with three things:

1. **Cross-model validation.** The same change goes to models from
   different families (Anthropic, OpenAI, Google). Two independent models
   flagging the same function is a strong signal.
2. **Persona specialisation.** Correctness, adversarial, security and
   quality reviewers each look for one class of issue instead of one
   generic pass.
3. **Structured grading.** The grader looks for explicit signals (P0-P3
   priorities, `SEVERITY:` markers, verdict keywords). Absent proof is
   graded as unsure, never as verified.

## How it works

![How Pi Harness works](docs/images/how-it-works.jpg)

The entry scripts source four small bash libraries. `pi-harness-config`
detects which providers are configured (a LiteLLM proxy, an Anthropic key,
an OpenAI key) and picks a primary and secondary model. `pi-review-engine`
routes each review through [omp](https://github.com/can1357/oh-my-pi)
(preferred: its built-in reviewer prompt plus an appended persona focus) or
falls back to [Pi](https://pi.dev) with standalone persona prompts that
enforce a `SEVERITY:` output format. `pi-harness-common` captures the input
once, enforces size limits and tracks child processes so Ctrl-C cleans up
every reviewer; each reviewer runs in its own agent directory to avoid
SQLite lock contention between parallel instances. `pi-grades` strips code
blocks from each output, scans it line by line with negation handling
("No P0 issues" is not a P0), and assigns a grade; the worst grade sets the
verdict.

The grader on its own, run against four sample reviewer outputs (the
inputs are short hand-written samples; the grades are the real output of
`pi-grades`):

![pi-grades grading four sample reviewer outputs](docs/images/terminal.png)

### Grading

| Grade | Meaning | Passing? |
|-------|---------|----------|
| **PERFECT** | Clean signal, no findings | Yes |
| **VERIFIED** | Clean signal, only non-blocking findings | Yes |
| **PARTIAL** | No clear signal either way | No |
| **FEEDBACK** | Non-blocking findings, no clean signal | No |
| **FAILED** | P0, CRITICAL/HIGH, "incorrect" verdict or "Do not merge" | No |

Blocking signals always win: a P0 finding is FAILED regardless of any clean
signal in the same output. Exit codes: `0` all passed, `1` issues found,
`2` incomplete (reviewer failures or empty output).

### Personas

| Persona | Focus |
|---------|-------|
| **correctness** | Logic errors, off-by-one, null handling, races, missed edge cases |
| **adversarial** | Input validation gaps, error-handling holes, resource exhaustion, state corruption |
| **security** | OWASP Top 10, injection, auth gaps, secrets exposure, path traversal, SSRF |
| **quality** | Dead code, naming, duplication, complexity, testability |
| **verifier** | Intent against implementation, undocumented side effects, scope creep |

## Features

- Parallel multi-model, multi-persona review with a configurable cap
  (`PI_MAX_PARALLEL`, default 8) and per-reviewer timeout
  (`PI_REVIEW_TIMEOUT`, default 300 s).
- Provider auto-detection with overrides via a config file or
  `PI_HARNESS_MODELS`.
- Two engines (omp, Pi) behind one interface, with automatic fallback.
- Whole-file review mode that skips symlinks, files outside the working
  directory, secret-looking files (`.env`, `.pem`, `.key`, `credentials`)
  and binaries, so nothing sensitive is sent to a model API.
- Input size limits (`PI_MAX_INPUT_LINES`, `PI_MAX_INPUT_BYTES`).
- POSIX character classes in every regex for macOS and Linux portability.
- A summary block with the grade distribution and one verdict line:

```
=== SWARM SUMMARY ===
Launched: 8 | Failed: 0 | Empty: 0
Grades: PERFECT=2 VERIFIED=3 PARTIAL=1 FEEDBACK=2 FAILED=0
Passing: 5/8
=== VERDICT: FEEDBACK -- 2 reviewer(s) found issues needing correction ===
```

(The block above shows the format; the counts are illustrative.)

## Run it locally (for review)

Needs bash, git, Pi or omp, and at least one provider key
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or a LiteLLM entry in
`~/.pi/agent/models.json`). `setup/install.sh` detects providers, writes
`~/.config/pi-harness/config` and links the three scripts into
`~/.local/bin/`. Then, inside any git repo with changes:

```bash
pi-swarm --quick
```

Free for personal and non-commercial use with credit; commercial use needs
a licence. See [LICENSE](LICENSE) (PolyForm Noncommercial 1.0.0).

## Layout

```
pi-harness-config     provider auto-detection, model selection
pi-harness-common     input capture, size limits, cleanup
pi-review-engine      omp/pi routing, persona validation, timeouts
pi-grades             five-tier grader
prompts/              persona prompts for the Pi fallback path
scripts/              pi-review, pi-swarm, pi-verify
setup/install.sh      setup script
```

## Project status

Working tool at v2.0. The code last changed in May 2026. There is no automated test suite yet; the grader
(`pi-grades`) is the obvious first candidate.

## How it was built

Written with an AI coding assistant and then pointed at itself: the
harness reviewed its own code over twelve rounds before the v2.0 commit
(2026-05-04), and the same day a run on real omp output showed that the
grader missed omp's emoji severity markers, which led to the first fix. The full story, with dates and the decisions behind them, is in
[docs/BUILD-STORY.md](docs/BUILD-STORY.md).

## Credits

- [Pi](https://pi.dev) and [omp (oh-my-pi)](https://github.com/can1357/oh-my-pi),
  the coding-agent CLIs the reviews run on.
- [LiteLLM](https://github.com/BerriAI/litellm), an optional provider proxy.

## Author

Rico Rojas, https://rico-rojas.com
