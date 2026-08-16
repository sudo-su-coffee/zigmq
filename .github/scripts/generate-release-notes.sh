#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${TARGET_SHA:?TARGET_SHA is required}"

previous_tag="${PREVIOUS_TAG:-}"
custom_notes="${CUSTOM_RELEASE_NOTES:-}"

printf '# %s\n\n' "$RELEASE_VERSION"
printf 'Automated release notes for commit `%s`.\n\n' "$TARGET_SHA"

if [[ -n "$previous_tag" ]]; then
  printf 'Changes since `%s`.\n\n' "$previous_tag"
  commit_range="$previous_tag..$TARGET_SHA"
else
  printf 'Changes since the beginning of the repository history.\n\n'
  commit_range="$TARGET_SHA"
fi

if [[ -n "$custom_notes" ]]; then
  printf '## Maintainer notes\n\n%s\n\n' "$custom_notes"
fi

declare -a breaking=()
declare -a features=()
declare -a fixes=()
declare -a performance=()
declare -a documentation=()
declare -a maintenance=()
declare -a other=()

while IFS=$'\t' read -r subject short_sha; do
  [[ -z "$subject" ]] && continue
  lower_subject="${subject,,}"
  if [[ "$subject" == *"BREAKING CHANGE"* || "$subject" =~ ^[[:alnum:]_-]+!:\  ]]; then
    breaking+=("- ${subject} (\`${short_sha}\`)")
    continue
  fi

  type="${lower_subject%%:*}"
  type="${type%%(*}"
  case "$type" in
    feat|feature|add|enhancement)
      features+=("- ${subject} (\`${short_sha}\`)")
      ;;
    fix|bug|bugfix)
      fixes+=("- ${subject} (\`${short_sha}\`)")
      ;;
    perf|performance|optimize|optimization)
      performance+=("- ${subject} (\`${short_sha}\`)")
      ;;
    docs|doc|documentation)
      documentation+=("- ${subject} (\`${short_sha}\`)")
      ;;
    ci|build|chore|refactor|test|tests|maintenance)
      maintenance+=("- ${subject} (\`${short_sha}\`)")
      ;;
    *)
      other+=("- ${subject} (\`${short_sha}\`)")
      ;;
  esac
done < <(git log --no-merges --format='%s%x09%h' "$commit_range")

print_section() {
  local title="$1"
  shift
  local -n entries="$1"
  if ((${#entries[@]} == 0)); then
    return
  fi
  printf '## %s\n\n' "$title"
  printf '%s\n' "${entries[@]}"
  printf '\n'
}

print_section "Breaking changes" breaking
print_section "Features" features
print_section "Fixes" fixes
print_section "Performance" performance
print_section "Documentation" documentation
print_section "Maintenance" maintenance
print_section "Other changes" other
