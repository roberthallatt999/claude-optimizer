# Contributing

Contributions to improve Claude Optimizer are welcome!

## Ways to Contribute

### Report Issues

Found a bug or have a suggestion?
- Open an issue on GitHub
- Include your stack, command used, and error output
- Provide minimal reproduction steps

### Improve Documentation

- Fix typos or clarify instructions
- Add examples or use cases
- Translate documentation

### Add Stack Support

Want to add a new stack?

1. Create `projects/{stack-name}/` directory
2. Add templates:
   - `CLAUDE.md.template`
   - `.claude/rules/` - Stack-specific rules
   - `.vscode/settings.json` - IDE configuration
3. Update detection logic in `setup-project.sh`
4. Test with real project
5. Submit pull request

### Improve Detection Logic

Enhance technology detection:

1. Edit `setup-project.sh` functions:
   - `detect_frontend_tools()`
   - `detect_template_group()`
   - `detect_addons()`
2. Test with various project structures
3. Update documentation
4. Submit pull request

## Development Setup

### Clone Repository

```bash
git clone https://github.com/roberthallatt/claude-optimizer.git
cd claude-optimizer
```

### Create Test Projects

```bash
mkdir -p ~/test-projects/{ee,craft,nextjs}
```

### Test Changes

```bash
ai-config \
  --dry-run \
  --stack=expressionengine \
  --project=~/test-projects/ee
```

## Code Style

### Bash Scripts

- Use `set -e` for error handling
- Quote all variable expansions: `"$VAR"`
- Use descriptive function names
- Add comments for complex logic
- Follow existing patterns

### Markdown

- Use ATX-style headers (`#`)
- Include code examples
- Link to related documentation
- Use fenced code blocks with language identifiers

### Templates

- Use `{{VARIABLE}}` syntax for substitutions
- Keep formatting consistent across stacks
- Test variable substitution works
- Don't hardcode project-specific values

## Testing Checklist

Before submitting pull request:

- [ ] Test with `--dry-run`
- [ ] Test actual deployment
- [ ] Test `--refresh` on existing project
- [ ] Verify VSCode settings work
- [ ] Check syntax highlighting
- [ ] Verify MCP configuration (if applicable)
- [ ] Update relevant documentation
- [ ] No broken links in docs

## Documentation Standards

### File Organization

```
docs/
├── getting-started/  # Installation and setup
├── guides/           # How-to guides
├── reference/        # Technical reference
└── development/      # Contributing and status
```

### Writing Style

- Be concise and direct
- Use examples liberally
- Link to related content
- Include troubleshooting sections
- Use tables for comparisons
- Use code blocks for commands

### Update Documentation

When making changes:

1. Update relevant guide in `docs/guides/`
2. Update reference if needed
3. Update `docs/README.md` if new section added
4. Update root `README.md` if major feature added

## Pull Request Process

1. **Fork the repository**
2. **Create feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make changes**
4. **Test thoroughly**
5. **Update documentation**
6. **Commit with clear messages**
   ```bash
   git commit -m "feat: add WordPress Multisite support"
   ```
7. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```
8. **Open pull request**
   - Describe changes
   - Link related issues
   - Include testing notes

## Commit Message Format

Follow conventional commits:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code refactoring
- `test:` - Testing changes
- `chore:` - Maintenance

**Examples:**
```
feat(craftcms): add Craft 5 support
fix(setup): correct Alpine.js detection in nested dirs
docs(vscode): add troubleshooting section
refactor(setup): extract detection to separate functions
```

## Getting Help

- **Questions:** Open GitHub discussion
- **Bugs:** Open GitHub issue
- **Ideas:** Open GitHub issue with "enhancement" label

## Code of Conduct

Be respectful, constructive, and professional. This is a collaborative project to help developers work more effectively.

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT).

## Thank You!

Every contribution, no matter how small, helps improve this project for everyone.
