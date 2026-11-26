# Contributing

How to change ai-config itself and check you haven't broken anything.

## Get the code

```bash
git clone https://github.com/roberthallatt999/claude-optimizer.git
```

```bash
cd claude-optimizer
```

## Run the tests

Run every suite, several at once (a full run takes about as long as the slowest suite, around 6 minutes):

```bash
./run-tests.sh
```

Run only the suites you name. The `test-` and `.sh` parts are optional:

```bash
./run-tests.sh safety-guard refresh-additive
```

The same tests run on GitHub, on macOS and Ubuntu, for every push. Shell scripts must also pass:

```bash
shellcheck -S warning setup-project.sh
```

**Every change needs a test** in the matching `test-*.sh` file. A bug fix needs a test that would have caught the
bug.

## Try a change on a scratch project

Make an empty folder:

```bash
mkdir -p ~/test-projects/ee
```

Preview a setup in it:

```bash
./setup-project.sh --dry-run --stack=expressionengine --project=$HOME/test-projects/ee
```

Then set it up for real and check it:

```bash
./setup-project.sh --stack=expressionengine --project=$HOME/test-projects/ee
```

```bash
./setup-project.sh --doctor --project=$HOME/test-projects/ee
```

## Common changes

| You want to | Where | Remember |
|---|---|---|
| Change what a stack gets | `projects/<stack>/` | No script change needed: stack files win over `projects/common/` |
| Add a stack | A new `projects/<stack>/` folder, plus detection in `setup-project.sh` | Add cases to `test-stack-detection.sh`, and a row to the [stacks page](../reference/stacks.md) |
| Detect a new front-end tool | The list in `projects/common/detect-frontend.sh` | Add a case to `test-frontend-detection.sh` |
| Change the safety guard | `projects/common/hooks/safety-guard.sh` | Add a case to `test-safety-guard.sh`, including one that tries to get round your change |
| Change a `CLAUDE.md` section | `projects/common/<section>.md` | Keep the `BEGIN`/`END` marker name the same everywhere `setup-project.sh` uses it |
| Ship a new file to projects | Use `install_file` or `install_rendered` in `setup-project.sh` | Never copy straight over a project's file. These functions keep the user's edits and make backups. `test-refresh-additive.sh` checks it |

## Style

- **Bash:** `set -e`, quote every variable (`"$VAR"`), clear function names. Comments say *why*, not what.
- **Templates:** `{{UPPERCASE}}` placeholders. Nothing specific to one real project.
- **Commits:** conventional format, such as `fix(detect): skip Python virtual environments`. Types: `feat`, `fix`,
  `docs`, `refactor`, `test`, `chore`.

## Writing these docs

These pages are read in a browser, and their commands are copied straight into Terminal. So:

- **One command per box.** Don't chain commands with `&&` or add `\` line breaks.
- **No comments inside command boxes.** zsh, the Mac's default shell, doesn't treat a pasted `# note` as a comment,
  so the command fails. Put the explanation in the sentence above the box.
- **No `$` prompt** in front of commands.
- **Commands should work as pasted.** Use `cd` and then `--project=.`, rather than a path the reader has to edit.
  If a placeholder can't be avoided, write it `<like-this>` and say what to put there.
- **Mark file contents by type:** `ini`, `json` or `yaml`. Use `bash` only for things to run, and `text` for
  things typed inside Claude Code.
- **Plain words.** Short sentences, "you", and the result before the detail. If a page needs a term like "hook"
  or "MCP", say what it means the first time.

Add a new page to the menu in `index.html` and to the list in `docs/README.md`. To see your changes:

```bash
./serve-docs.sh
```

## Reporting a problem

Open an [issue](https://github.com/roberthallatt999/claude-optimizer/issues) with the stack, the command you ran
and what it printed.

## Licence

Contributions are licensed under the project's MIT licence.
