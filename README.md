# package-release-tracker.sh 

A single bash script that generates an HTML report of download statistics for your GitHub releases. It auto-discovers projects by scanning your [Homebrew taps](https://docs.brew.sh/Taps) and [Scoop buckets](https://github.com/ScoopInstaller/Scoop/wiki/Buckets), then pulls version history and per-asset download counts from the GitHub API.

## Requirements

- `bash`, `curl`, `jq`
- A GitHub account with one or more `homebrew-*` and/or `scoop-*` repos

## Usage

```bash
./releases.sh [options] <github-owner> [output-file]
```

Options:

| Flag | Description |
|------|-------------|
| `--tap <repo>` | Homebrew tap repo name (repeatable; skips auto-discovery) |
| `--bucket <repo>` | Scoop bucket repo name (repeatable; skips auto-discovery) |

```bash
# Auto-discover all homebrew-* and scoop-* repos for a user
./releases.sh georgemandis

# Specify output file
./releases.sh georgemandis my-report.html

# Explicit tap(s) — skips auto-discovery
./releases.sh --tap homebrew-tap someuser
./releases.sh --tap homebrew-tools --tap homebrew-extras someuser

# Use a token for higher rate limits (and to avoid the 60 req/hr unauthenticated limit)
GITHUB_TOKEN=ghp_xxx ./releases.sh georgemandis

# Try it against some bigger projects
./releases.sh aws              # SAM CLI, copilot, eksctl, and ~20 other tools
./releases.sh charmbracelet    # gum, glow, vhs, soft-serve, and more
./releases.sh goreleaser       # the release pipeline tool itself
./releases.sh derailed          # k9s, popeye (per-project taps)
```

## How it works

1. Auto-discovers all `homebrew-*` and `scoop-*` repos for the given owner (or uses explicitly provided ones via `--tap`/`--bucket`)
2. Scans each tap for `.rb` formulas (in `Formula/` or the repo root) and each bucket for `.json` manifests. For single-project taps (e.g. `homebrew-xpra`), derives the project name from the repo name.
3. Deduplicates and fetches release data for each discovered project
4. Sums `download_count` across all release assets per version
5. Outputs a self-contained HTML page with an overview table and per-project breakdowns

API responses are cached locally (`.api-cache/`, 1 hour TTL) to avoid hammering the GitHub API during development.

## What it tracks

GitHub counts every download of a release asset. When someone runs `brew install yourname/tap/tool`, Homebrew downloads the tarball from your GitHub release — that increments the counter. Same with Scoop on Windows. It can't distinguish between package manager installs and direct browser downloads, but for platform-specific binaries it's a reasonable proxy.

Projects without release assets (i.e. no downloadable binaries/tarballs attached to releases) won't have any download data to report. If your formula or manifest points somewhere other than GitHub release assets, this tool won't capture those downloads.

This only works for projects distributed through your own taps and buckets. Popular projects that have graduated to [homebrew-core](https://github.com/Homebrew/homebrew-core) or Scoop's [main bucket](https://github.com/ScoopInstaller/Main) are installed from those central repositories instead — their downloads won't hit your GitHub release assets, and their formulas/manifests live in repos you don't own. If your tap contains a `tap_migrations.json` pointing to homebrew-core, that's a sign the project has moved on.

## Output

A single, self-contained HTML file with light/dark mode support. No dependencies, no build step.

## License

MIT
