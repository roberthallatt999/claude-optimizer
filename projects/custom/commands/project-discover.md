# /project-discover

Analyze this codebase and generate comprehensive AI assistant configuration.

## Your Task

You are tasked with analyzing this project and generating custom configuration for AI coding assistants. This includes researching best practices for the detected technologies and creating appropriate rules, workflows, and documentation.

## Step 1: Analyze the Codebase

Scan the project and identify:

1. **Project Structure**
   - Directory layout and organization
   - Entry points and main files
   - Configuration files

2. **Languages & Frameworks**
   - Primary programming language(s)
   - Frameworks in use (React, Vue, Laravel, Django, etc.)
   - Template engines (Twig, Blade, EJS, etc.)

3. **Build Tools & Package Managers**
   - npm, yarn, pnpm, composer, pip, cargo, etc.
   - Build tools (Vite, Webpack, esbuild, etc.)
   - Task runners

4. **Testing Setup**
   - Test frameworks (Jest, Vitest, PHPUnit, pytest, etc.)
   - Test file patterns and locations

5. **Code Quality Tools**
   - Linters (ESLint, Pylint, PHP_CodeSniffer)
   - Formatters (Prettier, Black)
   - Type checkers (TypeScript, mypy)

6. **Development Environment**
   - Docker, DDEV, or other containerization
   - Environment configuration (.env files)
   - Local development URLs

## Step 2: Research Best Practices

For each detected technology, research and document:

1. **Coding Standards**
   - Official style guides
   - Community conventions
   - Common patterns

2. **Security Best Practices**
   - OWASP guidelines for the stack
   - Authentication/authorization patterns
   - Input validation approaches

3. **Performance Guidelines**
   - Caching strategies
   - Optimization techniques
   - Common performance pitfalls

4. **Testing Strategies**
   - Recommended test coverage
   - Testing patterns for the framework
   - Mocking and fixture approaches

## Step 3: Decide What Git Should Ignore

The goal: nothing the app needs to run or deploy is ignored, and nothing secret, generated or
machine-specific is committed. A file wrongly ignored drops out of the next commit after a CMS
upgrade or a new add-on, and the deployed site breaks. ai-config's rules sit below the
`(Added by ai-config …)` header in `.gitignore`.

1. **Map the codebase**: framework, CMS, add-ons/plugins, build tools, and where each lives
   (a renamed EE system folder such as `ermin/`, an app in `frontend/` or `backend/`, a
   WordPress core in a subfolder).
2. **Check the official sources** for each: the starter `.gitignore` in the framework's
   template repo or scaffolder, and its docs on version control and environment files. Note
   what they ignore *and* what they say must be committed: config files, placeholder files
   that keep a folder in place (`index.html`, `.gitkeep`, nested `.gitignore`), lockfiles,
   `.env.example`, and `.env.*` defaults some frameworks commit.
3. **Test the rules against this repo** without opening files:
   - `git ls-files -ci --exclude-standard` lists tracked files that ignore rules match, and
     `git check-ignore -v --no-index <path>` names the rule. Every hit is a file git would
     leave out if it were new.
   - `git status --ignored --porcelain` shows what is ignored now.
   - Bare names (`cache/`, `logs/`, `vendor/`, `dist/`, `build/`) match at any depth, and on
     macOS case-insensitively: `database.php` also hides `Database.php`.
4. **Fix**:
   - An ai-config rule that's wrong for this codebase: add `skip = <pattern>` under
     `[gitignore]` in `ai-config.conf`, then run `ai-config --refresh`. Deleting the line by
     hand doesn't last, because a refresh adds it back.
   - A rule the project needs: add it to `.gitignore` above ai-config's header, anchored with
     a leading `/` to where the stack keeps it. When the app needs the folder but not its
     contents, ignore `/path/*` and re-include the placeholder (`!/path/index.html`).
5. **Never** un-ignore a secret (`.env`, keys, credentials, config holding passwords) to make
   something work, and never open such a file to decide. If a secret file is already tracked,
   report it; don't take it out of git yourself.
6. Run `ai-config --doctor` and confirm it reports no `.gitignore` rule matching tracked files.

## Step 4: Generate Configuration

Create or update the following files:

### CLAUDE.md
Update with:
- Accurate project overview
- Complete directory structure
- All development commands
- Framework-specific patterns and examples

### .claude/rules/
Create rules for each detected technology:
- `{framework}-patterns.md` - Framework-specific patterns
- `{language}-standards.md` - Language coding standards
- `testing-guidelines.md` - Testing requirements
- `security-requirements.md` - Security guidelines

### .claude/agents/
Create relevant specialist agents:
- Backend specialist (if applicable)
- Frontend specialist (if applicable)
- Testing specialist
- Security reviewer

### Other AI Assistants
If deployed with --with-all, also update:
- `.github/copilot-instructions.md`
- `AGENTS.md`
- `CONVENTIONS.md`

## Step 5: Report Findings

After analysis, provide a summary:

```
## Discovery Report

### Detected Stack
- Primary: [framework/language]
- Frontend: [if applicable]
- Database: [if applicable]
- Testing: [frameworks]

### Generated Configuration
- [x] Updated CLAUDE.md
- [x] Created X rules in .claude/rules/
- [x] Created X agents in .claude/agents/
- [x] Updated other AI configs (if applicable)

### .gitignore
- Skipped ai-config rules: [pattern — why — source URL]
- Added project rules: [pattern — why — source URL]
- Tracked secret files found: [paths, or none]

### Recommendations
1. [Suggested improvements]
2. [Missing configurations to consider]
3. [Best practices to implement]
```

## Notes

- Be thorough but avoid over-engineering
- Focus on patterns already present in the codebase
- Respect existing conventions even if they differ from defaults
- Ask clarifying questions if the project type is ambiguous
