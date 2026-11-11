# Skills and Profiles

ai-config serves more than one kind of work (an employer, volunteer projects, side work), so
nothing in this repo assumes who you are. Skills come in three tiers, and who you are comes
from a **profile** kept in a private repo.

## Skill tiers

| Tier | Lives in | Reaches Claude | Cost when unused |
|------|----------|----------------|------------------|
| Global | `global-skills/` (this repo) | Linked into `~/.claude/skills/` by `install.sh` and every `ai-config` run | Its description, in every session |
| Private | `~/.config/ai-config/skills/` (private repo) | Linked the same way | Its description, in every session |
| Design | `design-skills/` (this repo) | Copied into a project's `.claude/skills/` by `ai-config` | Nothing outside that project |

**Global:** `noslop` (pages for a reader) and `humanizer` (prose edits). Both are useful in
any session, whatever the project.

**Design:** pinned third-party front-end skills, deployed only where a front end is being
designed.

| Skill | Deployed to |
|-------|-------------|
| `impeccable` (+ 4 agents) | JS front-end stacks; CMS stacks with `--design-skills` |
| `web-design-guidelines` | Same |
| `gsap-*` (8 skills) | Same, and only where GSAP is detected; `gsap-react` needs React, `gsap-frameworks` Vue or Svelte |

- Turn them on for a CMS project with `--design-skills` or `design-skills = true` in
  `ai-config.conf`. Turn them off anywhere with `--no-design-skills` or `design-skills = false`.
- Impeccable's design-detector hook stays off unless you run `/impeccable hooks on` in the
  project, and `IMPECCABLE_NO_TELEMETRY=1` is set in the project's `settings.local.json`.
- A design skill deleted from a project stays deleted on `--refresh`. List it under
  `[exclude]` in `ai-config.conf` to make that survive a fresh clone.

### Pinning and updating

Every third-party skill is listed in `vendor/skills.conf` with its repo and commit. Any change
to the upstream text is a patch in `vendor/patches/`.

```bash
scripts/vendor-skills.sh --list
scripts/vendor-skills.sh --bump impeccable        # newest commit, rebuild, then: git diff
scripts/vendor-skills.sh --fetch                  # rebuild every skill at its pinned commit
```

Nothing runs at deploy time: projects get the committed copy. A patch that no longer applies
stops the bump and keeps the old copy.

### Rejected candidates (vetted 2026-11-11)

| Skill | Why it was rejected |
|-------|---------------------|
| Taste | A 39 MB site generator with a Stop hook |
| Hallmark | Its own description refuses existing designs |
| UI/UX Pro Max | 7 skills (~15k tokens) and stock palettes that fight a client's brand |
| Better Icons | A wrapper for an unpinned npm tool that edits MCP config |
| React Bits | No free skill exists |
| skillui | A hard-coded API key, and it sends URLs to a third party |
| Playwright CLI | Already covered by the Playwright plugin |

## Profiles

A profile says who you are in one context:

- `name`, `organization`, `voice` (I or we), `spelling`
- `share_domain`: where noslop publishes pages
- `sensitive`: personal information that never sits behind a shared passcode
- `not_for`: what noslop isn't for

See `profiles/example.conf`.

```
~/.config/ai-config/            ← a private git repo, not this one
├── profile                     ← this machine's default, e.g. "cps" or "personal"
├── profiles/
│   ├── cps.conf
│   └── personal.conf
└── skills/                     ← your own skills (linked into ~/.claude/skills/)
```

The active profile is the first of these:

1. `AI_CONFIG_PROFILE`
2. `profile = <name>` under `[options]` in the project's `ai-config.conf`
3. The machine default in `~/.config/ai-config/profile`

`global-skills/noslop/scripts/profile.sh` prints it. Dev containers mount
`~/.config/ai-config` read-only.

### Setting up and editing your profiles

Every file is in `~/.config/ai-config/`, outside this repo:

| File | What it sets |
|------|--------------|
| `profile` | This computer's default profile: one word, e.g. `personal` or `cps` |
| `profiles/<name>.conf` | One context's details: name, organization, share domain, spelling, what's sensitive |

**1. Choose this computer's default.** On a personal computer:

```bash
echo personal > ~/.config/ai-config/profile
```

On a work computer, use `echo cps` instead.

**2. Fill in the profile.**

```bash
code ~/.config/ai-config/profiles/personal.conf
```

The keys most likely to change:

- `organization`: empty for your own work, or the group you're volunteering for.
- `share_domain`: where noslop publishes pages, e.g. `share.yourdomain.ca`. Empty means
  noslop builds pages locally and publishes nothing.
- `sensitive`: whose personal information must never sit behind a shared passcode.

**3. Projects that need a different profile.** On a computer that defaults to `personal`,
a CPS project names its profile in `ai-config.conf`:

```ini
[options]
profile = cps
```

**4. A side-gig client with its own details.** Copy the profile, edit the copy, and name
it in that client's projects:

```bash
cp ~/.config/ai-config/profiles/personal.conf ~/.config/ai-config/profiles/<client>.conf
```

Then set `profile = <client>` in each of that client's projects.

**5. Check which profile is active.** Run this from inside a project folder:

```bash
~/.claude/skills/noslop/scripts/profile.sh
```

It prints the profile's name, where the choice came from (`from=`), and each value.
`profile=none` means no profile matched, so noslop will ask who the page is from.

**6. Save your changes.** `~/.config/ai-config` is a git repo, so commit and push there:

```bash
cd ~/.config/ai-config && git commit -am "Update personal profile" && git push
```

### A new machine

```bash
git clone git@github.com:<you>/ai-config-profiles.git ~/.config/ai-config
echo personal > ~/.config/ai-config/profile      # this machine's default
git clone https://github.com/roberthallatt999/claude-optimizer.git && ./claude-optimizer/install.sh
```

The Cloudflare token for noslop's pages isn't in either repo. Run
`~/.claude/skills/noslop/scripts/cloudflare.sh setup` on each machine.
