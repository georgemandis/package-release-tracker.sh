# github-release-download-reporting

A single bash script that generates an HTML report of download statistics for your GitHub releases. It auto-discovers projects by scanning your [Homebrew tap](https://docs.brew.sh/Taps) and [Scoop bucket](https://github.com/ScoopInstaller/Scoop/wiki/Buckets), then pulls version history and per-asset download counts from the GitHub API.

## Requirements

- `bash`, `curl`, `jq`
- A GitHub account with a `homebrew-tap` and/or `scoop-bucket` repo containing formulas/manifests

## Usage

```bash
./releases.sh [options] <github-owner> [output-file]
```

Options:

| Flag | Description | Default |
|------|-------------|---------|
| `--tap <repo>` | Homebrew tap repo name | `homebrew-tap` |
| `--bucket <repo>` | Scoop bucket repo name | `scoop-bucket` |

```bash
# Generate releases.html for a given GitHub user
./releases.sh georgemandis

# Specify output file
./releases.sh georgemandis my-report.html

# Custom tap/bucket repo names
./releases.sh --tap my-homebrew-formulas --bucket my-scoop-manifests someuser

# Use a token for higher rate limits
GITHUB_TOKEN=ghp_xxx ./releases.sh georgemandis
```

## How it works

1. Scans `<owner>/homebrew-tap/contents/Formula` for `.rb` files and `<owner>/scoop-bucket/contents/` for `.json` files
2. Deduplicates and fetches release data for each discovered project
3. Sums `download_count` across all release assets per version
4. Outputs a self-contained HTML page with an overview table and per-project breakdowns

API responses are cached locally (`.api-cache/`, 1 hour TTL) to avoid hammering the GitHub API during development.

## What it tracks

GitHub counts every download of a release asset. When someone runs `brew install yourname/tap/tool`, Homebrew downloads the tarball from your GitHub release — that increments the counter. Same with Scoop on Windows. It can't distinguish between package manager installs and direct browser downloads, but for platform-specific binaries it's a reasonable proxy.

Projects without release assets (i.e. no downloadable binaries/tarballs attached to releases) won't have any download data to report. If your formula or manifest points somewhere other than GitHub release assets, this tool won't capture those downloads.

## Output

A single, self-contained HTML file with light/dark mode support. No dependencies, no build step.

## License

MIT
