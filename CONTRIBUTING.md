### Contributing

Code contributions are welcome!

### Development setup

Install [lefthook](https://lefthook.dev), [shellcheck](https://www.shellcheck.net)
and [gitleaks](https://gitleaks.io), then enable the git hooks:

    lefthook install

The hooks run the same lint and secret-scan gates as CI
(`.github/workflows/ci.yml`) on commit and push.

### Reporting a bug

If you find a bug please report it in the issues. When reporting a bug please
attach:
- a file symlinked to `~/.tmux/resurrect/last`.
- your `.tmux.conf`
- if you're getting an error paste it to a [gist](https://gist.github.com/) and
  link it in the issue
