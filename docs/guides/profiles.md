# Profiles and skills

ai-config is used for different kinds of work: a job, volunteer projects, side work. A **profile** says who you
are in one of them, so a report for a client doesn't go out under your employer's name.

## What a profile holds

A profile is a small text file. The main lines:

| Line | Meaning |
|---|---|
| `name`, `organization` | Who pages and reports are from |
| `voice` | `I` or `we` |
| `spelling` | For example `canadian` |
| `share_domain` | Where the `noslop` skill publishes pages, such as `share.example.org`. Leave it empty to publish nothing |
| `sensitive` | Whose personal information must never sit behind a shared password |
| `brand_primary`, `font_heading`, `logo_on_light`… | Optional: your organization's colours, fonts and logo on published pages |

`profiles/example.conf` in this repository lists every line.

## Where profiles live

Profiles are personal, so they live in your own **private** git repository, not in this one:

```text
~/.config/ai-config/
├── profile            this computer's default profile, one word
├── folders            which profile to use under which folder
├── profiles/
│   ├── work.conf
│   ├── personal.conf
│   └── client.conf
└── skills/            your own skills
```

## Set up your profiles

**1. Pick this computer's default.** For example, on a personal computer:

```bash
echo personal > ~/.config/ai-config/profile
```

**2. Fill in the profile.** Open it in VS Code:

```bash
code ~/.config/ai-config/profiles/personal.conf
```

**3. Add a profile for a client** by copying one and editing the copy:

```bash
cp ~/.config/ai-config/profiles/personal.conf ~/.config/ai-config/profiles/client.conf
```

**4. Save your changes** to your private repository:

```bash
git -C ~/.config/ai-config commit -am "Update profiles"
```

```bash
git -C ~/.config/ai-config push
```

## Which profile a project uses

Each project uses exactly one profile. ai-config takes the first of these that applies:

1. the `AI_CONFIG_PROFILE` environment variable
2. `profile = <name>` under `[options]` in the project's `ai-config.conf`
3. the `folders` file: the longest folder that contains the project wins
4. this computer's default, in `~/.config/ai-config/profile`

A `folders` file looks like this:

```ini
~/sites/client-work = client
~/sites/client-work/my-own-site = personal
```

To see which profile is active, run this from inside a project folder:

```bash
~/.claude/skills/noslop/scripts/profile.sh
```

It prints the profile's name, where the choice came from, and each value. `profile=none` means nothing matched.
`ai-config --doctor` also shows each project's profile.

## Publishing pages per profile

The `noslop` skill can publish a page behind a password on your profile's share domain, through Cloudflare. Each
profile keeps its own Cloudflare account and token, so one client's page never goes out under another's account.

Set it up once per profile, from inside a project that uses it:

```bash
~/.claude/skills/noslop/scripts/cloudflare.sh setup
```

If two profiles publish to domains in the same Cloudflare account, one can borrow the other's setup: add
`cloudflare = <other profile>` to its `.conf` file.

## A new computer

Get your profiles:

```bash
git clone git@github.com:<you>/<your-profiles-repo>.git ~/.config/ai-config
```

Pick this computer's default:

```bash
echo personal > ~/.config/ai-config/profile
```

Then [install ai-config](../getting-started/installation.md). The Cloudflare token isn't stored in either
repository, so run the `cloudflare.sh setup` step above on each computer.

## Skills: three kinds

| Kind | Where it comes from | Where it's available |
|---|---|---|
| **Shared** (`noslop`, `humanizer`) | `global-skills/` in this repository | Every Claude Code session on your computer |
| **Your own** | `~/.config/ai-config/skills/` | Every session on your computer |
| **Design** (Impeccable, web-design-guidelines, GSAP) | `design-skills/` in this repository | Only in projects that build a front end |

- `noslop` makes pages and reports that someone else will read. `humanizer` edits writing so it sounds less
  machine-made.
- Design skills go to JavaScript projects automatically. Add them to a CMS project with `--design-skills`, or
  leave them out with `--no-design-skills`. The GSAP skills only go where the project uses GSAP.

### Updating the design skills (for whoever maintains ai-config)

Each outside skill is pinned to an exact version in `vendor/skills.conf`, so nobody else's change reaches Claude
without review. Local changes are patches in `vendor/patches/`.

List them:

```bash
scripts/vendor-skills.sh --list
```

Update one to its newest version, then review with `git diff`:

```bash
scripts/vendor-skills.sh --bump impeccable
```

If a patch no longer applies, the update stops and the old copy is kept.
