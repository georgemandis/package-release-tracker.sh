#!/usr/bin/env bash
set -euo pipefail

# Usage: ./releases.sh [options] <github-owner> [output-file]
# Generates an HTML report of download stats for all projects found in
# the owner's Homebrew taps and Scoop buckets.
#
# Options:
#   --tap <repo>     Homebrew tap repo name (repeatable; skips auto-discovery)
#   --bucket <repo>  Scoop bucket repo name (repeatable; skips auto-discovery)
#
# By default, discovers all homebrew-* and scoop-* repos for the owner.
#
# Requires: curl, jq
# Optional: GITHUB_TOKEN env var for authenticated API requests

declare -a TAP_REPOS=()
declare -a BUCKET_REPOS=()

# Parse options
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --tap)    TAP_REPOS+=("$2"); shift 2 ;;
    --bucket) BUCKET_REPOS+=("$2"); shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

GITHUB_OWNER="${1:-}"
OUTPUT="${2:-releases.html}"

if [ -z "$GITHUB_OWNER" ]; then
  echo "Usage: $0 [options] <github-owner> [output-file]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --tap <repo>     Homebrew tap repo name (repeatable; skips auto-discovery)" >&2
  echo "  --bucket <repo>  Scoop bucket repo name (repeatable; skips auto-discovery)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_BASE="https://api.github.com"
CACHE_DIR="$SCRIPT_DIR/.api-cache"
CACHE_MAX_AGE=3600  # 1 hour

mkdir -p "$CACHE_DIR"

# Auth header if token is available
AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
fi

# Helper: authenticated curl
gh_curl() {
  local -a headers=(-H "Accept: application/vnd.github+json")
  if [ -n "$AUTH_HEADER" ]; then
    headers+=(-H "$AUTH_HEADER")
  fi
  curl -sf "${headers[@]}" "$1"
}

# Cached API fetch
cached_fetch() {
  local url="$1"
  local cache_key
  cache_key=$(echo "$url" | sed 's|[^a-zA-Z0-9]|_|g')
  local cache_file="$CACHE_DIR/$cache_key"

  if [ -f "$cache_file" ]; then
    local file_age
    if [[ "$OSTYPE" == darwin* ]]; then
      file_age=$(( $(date +%s) - $(stat -f %m "$cache_file") ))
    else
      file_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
    fi
    if [ "$file_age" -lt "$CACHE_MAX_AGE" ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  local result
  result=$(gh_curl "$url") || return 1
  echo "$result" > "$cache_file"
  echo "$result"
}

# Format number with commas (e.g. 1234567 → 1,234,567)
format_number() {
  printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# Human-readable date from ISO 8601 (cross-platform)
format_date() {
  local iso_date="$1"
  date -jf "%Y-%m-%dT%H:%M:%SZ" "$iso_date" "+%b %d, %Y" 2>/dev/null \
    || date -d "$iso_date" "+%b %d, %Y" 2>/dev/null \
    || echo "$iso_date"
}

# --- Discover tap/bucket repos ---

# Auto-discover if no explicit --tap or --bucket flags were given
if [ ${#TAP_REPOS[@]} -eq 0 ] && [ ${#BUCKET_REPOS[@]} -eq 0 ]; then
  echo "Auto-discovering homebrew-* and scoop-* repos for $GITHUB_OWNER..." >&2
  for prefix in homebrew scoop; do
    # user: works for personal accounts, org: works for organizations — try both
    search_json=$(cached_fetch "$API_BASE/search/repositories?q=${prefix}+in:name+user:${GITHUB_OWNER}&per_page=100" 2>/dev/null) || true
    result_count=$(echo "$search_json" | jq '.total_count // 0' 2>/dev/null)
    if [ "${result_count:-0}" -eq 0 ]; then
      search_json=$(cached_fetch "$API_BASE/search/repositories?q=${prefix}+in:name+org:${GITHUB_OWNER}&per_page=100" 2>/dev/null) || continue
    fi
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      if [[ "$name" == homebrew-* ]]; then
        TAP_REPOS+=("$name")
      elif [[ "$name" == scoop-* ]]; then
        BUCKET_REPOS+=("$name")
      fi
    done < <(echo "$search_json" | jq -r '.items[].name')
  done
fi

if [ ${#TAP_REPOS[@]} -eq 0 ] && [ ${#BUCKET_REPOS[@]} -eq 0 ]; then
  echo "No homebrew-* or scoop-* repos found for $GITHUB_OWNER" >&2
  exit 1
fi

[ ${#TAP_REPOS[@]} -gt 0 ] && echo "Tap repos: ${TAP_REPOS[*]}" >&2
[ ${#BUCKET_REPOS[@]} -gt 0 ] && echo "Bucket repos: ${BUCKET_REPOS[*]}" >&2

# --- Discover projects from taps and buckets ---

homebrew_projects=""
for tap in "${TAP_REPOS[@]}"; do
  # Try Formula/ subdirectory first, then repo root
  found=$(cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$tap/contents/Formula" 2>/dev/null \
    | jq -r '.[].name | select(endswith(".rb")) | rtrimstr(".rb")') || true
  if [ -z "$found" ]; then
    found=$(cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$tap/contents/" 2>/dev/null \
      | jq -r '.[].name | select(endswith(".rb")) | rtrimstr(".rb")') || true
  fi
  if [ -z "$found" ]; then
    # Single-project tap: derive project name from repo name (strip "homebrew-" prefix)
    project_name="${tap#homebrew-}"
    # Verify the repo actually exists
    if cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$project_name" >/dev/null 2>&1; then
      found="$project_name"
    fi
  fi
  if [ -n "$found" ]; then
    homebrew_projects=$(printf '%s\n%s' "$homebrew_projects" "$found")
  fi
done

scoop_projects=""
for bucket in "${BUCKET_REPOS[@]}"; do
  found=$(cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$bucket/contents/" 2>/dev/null \
    | jq -r '.[].name | select(endswith(".json")) | rtrimstr(".json")') || true
  if [ -n "$found" ]; then
    scoop_projects=$(printf '%s\n%s' "$scoop_projects" "$found")
  fi
done

projects=$(printf '%s\n%s' "$homebrew_projects" "$scoop_projects" | grep -v '^$' | sort -u)

if [ -z "$projects" ]; then
  echo "No projects found in any discovered taps or buckets for $GITHUB_OWNER" >&2
  exit 1
fi

echo "Discovered projects: $(echo "$projects" | tr '\n' ' ')" >&2

# --- Collect data ---

declare -a project_names=()
declare -a project_descriptions=()
declare -a project_version_counts=()
declare -a project_total_downloads=()
declare -a project_rows=()
declare -a project_has_assets=()

while IFS= read -r project; do
  [ -z "$project" ] && continue
  echo "Fetching: $project" >&2

  repo_json=$(cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$project" 2>/dev/null) || {
    echo "  Warning: repo $project not found, skipping" >&2
    continue
  }
  description=$(echo "$repo_json" | jq -r '.description // "No description available."')

  releases_json=$(cached_fetch "$API_BASE/repos/$GITHUB_OWNER/$project/releases?per_page=100" 2>/dev/null) || {
    echo "  Warning: could not fetch releases for $project, skipping" >&2
    continue
  }

  release_count=$(echo "$releases_json" | jq 'length')
  if [ "$release_count" -eq 0 ]; then
    echo "  Warning: no releases for $project, skipping" >&2
    continue
  fi

  total_downloads=0
  version_count=0
  table_rows=""
  has_assets=false

  total_assets=$(echo "$releases_json" | jq '[.[].assets | length] | add // 0')
  if [ "$total_assets" -gt 0 ]; then
    has_assets=true
  fi

  while IFS=$'\t' read -r tag_name published_at downloads; do
    formatted_date=$(format_date "$published_at")
    release_url="https://github.com/${GITHUB_OWNER}/${project}/releases/tag/${tag_name}"
    if [ "$has_assets" = true ]; then
      table_rows="${table_rows}<tr><td><a href=\"${release_url}\">${tag_name}</a></td><td>${formatted_date}</td><td>$(format_number "$downloads")</td></tr>
"
    else
      table_rows="${table_rows}<tr><td><a href=\"${release_url}\">${tag_name}</a></td><td>${formatted_date}</td></tr>
"
    fi
    total_downloads=$((total_downloads + downloads))
    version_count=$((version_count + 1))
  done < <(echo "$releases_json" | jq -r '
    .[] | [
      .tag_name,
      .published_at,
      ([.assets[].download_count] | add // 0)
    ] | @tsv
  ')

  project_names+=("$project")
  project_descriptions+=("$description")
  project_version_counts+=("$version_count")
  project_total_downloads+=("$total_downloads")
  project_rows+=("$table_rows")
  project_has_assets+=("$has_assets")

  echo "  $project: $version_count versions, $total_downloads downloads" >&2
done <<< "$projects"

if [ ${#project_names[@]} -eq 0 ]; then
  echo "No projects with releases found." >&2
  exit 1
fi

# --- Grand totals ---

grand_versions=0
grand_downloads=0
for i in "${!project_names[@]}"; do
  grand_versions=$((grand_versions + project_version_counts[i]))
  grand_downloads=$((grand_downloads + project_total_downloads[i]))
done

UPDATED=$(date "+%b %d, %Y")

# --- Generate HTML ---

{
  cat << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
HTMLHEAD

  echo "<title>Releases — ${GITHUB_OWNER}</title>"

  cat << 'STYLE'
<style>
  :root {
    --fg: #222;
    --bg: #fff;
    --muted: #666;
    --border: #ddd;
    --link: #0366d6;
    --hover: #024ea2;
    --stripe: #f6f8fa;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --fg: #c9d1d9;
      --bg: #0d1117;
      --muted: #8b949e;
      --border: #30363d;
      --link: #58a6ff;
      --hover: #79c0ff;
      --stripe: #161b22;
    }
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    color: var(--fg);
    background: var(--bg);
    line-height: 1.6;
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem 1rem;
  }
  h1 { margin-bottom: 0.25rem; }
  h1 + p { color: var(--muted); margin-bottom: 1.5rem; }
  h2 {
    margin-top: 2.5rem;
    margin-bottom: 0.25rem;
    padding-bottom: 0.3rem;
    border-bottom: 1px solid var(--border);
  }
  h2 + p { color: var(--muted); margin-bottom: 0.75rem; font-size: 0.9rem; }
  a { color: var(--link); text-decoration: none; }
  a:hover { color: var(--hover); text-decoration: underline; }
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 0.75rem 0 1.5rem;
    font-size: 0.9rem;
  }
  th, td {
    text-align: left;
    padding: 0.4rem 0.75rem;
    border-bottom: 1px solid var(--border);
  }
  th { font-weight: 600; }
  tr:nth-child(even) { background: var(--stripe); }
  tfoot td { font-weight: 600; }
  .meta { color: var(--muted); font-size: 0.85rem; margin-top: 2rem; }
</style>
STYLE

  cat << 'HTMLMID'
</head>
<body>
HTMLMID

  echo "<h1>Releases</h1>"
  echo "<p>Download statistics for <a href=\"https://github.com/${GITHUB_OWNER}\">${GITHUB_OWNER}</a></p>"

  # Overview table
  echo "<table>"
  echo "<thead><tr><th>Project</th><th>Versions</th><th>Downloads</th></tr></thead>"
  echo "<tbody>"
  for i in "${!project_names[@]}"; do
    anchor=$(echo "${project_names[i]}" | tr '[:upper:]' '[:lower:]')
    if [ "${project_has_assets[i]}" = true ]; then
      dl_cell="$(format_number "${project_total_downloads[i]}")"
    else
      dl_cell="—"
    fi
    echo "<tr><td><a href=\"#${anchor}\">${project_names[i]}</a></td><td>${project_version_counts[i]}</td><td>${dl_cell}</td></tr>"
  done
  echo "</tbody>"
  echo "<tfoot><tr><td>Total</td><td>$(format_number "$grand_versions")</td><td>$(format_number "$grand_downloads")</td></tr></tfoot>"
  echo "</table>"

  # Per-project sections
  for i in "${!project_names[@]}"; do
    name="${project_names[i]}"
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    anchor="$lower"
    desc="${project_descriptions[i]}"

    echo "<h2 id=\"${anchor}\">${name}</h2>"
    echo "<p>${desc} — <a href=\"https://github.com/${GITHUB_OWNER}/${lower}\">github.com/${GITHUB_OWNER}/${lower}</a></p>"

    echo "<table>"
    if [ "${project_has_assets[i]}" = true ]; then
      echo "<thead><tr><th>Version</th><th>Released</th><th>Downloads</th></tr></thead>"
    else
      echo "<thead><tr><th>Version</th><th>Released</th></tr></thead>"
    fi
    echo "<tbody>"
    printf '%s' "${project_rows[i]}"
    echo "</tbody>"
    echo "</table>"
  done

  echo "<p class=\"meta\">Download totals are cumulative across all versions, architectures, and package managers.</p>"
  echo "<p class=\"meta\">Last updated: ${UPDATED}</p>"
  echo "</body></html>"
} > "$OUTPUT"

echo "" >&2
echo "Generated $OUTPUT" >&2
