#!/usr/bin/env bash
# Detect the Terraform roots changed by a pull request or push.
#
# A root is any folder under TF_ROOTS_DIR with a .tf file containing a backend
# block (any depth).
#   - any changed file in a root selects that root (.md ignored)
#   - a changed file outside any root (for example in a local module) selects
#     only the roots that use it, directly or through nested modules
#     (source = "./..." or "../...")
#   - removed / moved / renamed roots fail (orphaned state)
#   - artifact-name collisions fail
#
# Run from the repository root (full history checked out).
# Env:
#   EVENT            github.event_name
#   BASE_REF         github.base_ref        (pull_request)
#   BEFORE           github.event.before    (push)
#   SHA              github.sha             (push)
#   TF_ROOTS_DIR     default: workspace
#   TF_SELECT        optional. Skip change detection and select roots directly:
#                    "all" = every root, or one root folder (e.g. workspace/a/b).
#                    Used by the recovery and drift workflow.
# Outputs (GITHUB_OUTPUT): matrix, has_changes
set -euo pipefail

ROOTS_DIR="${TF_ROOTS_DIR:-workspace}"
BACKEND_RE='^[[:space:]]*backend[[:space:]]+"'
LOCAL_SRC_RE='^[[:space:]]*source[[:space:]]*=[[:space:]]*"\.\.?/'
ZERO_SHA="0000000000000000000000000000000000000000"

HEAD_REV=$(git rev-parse HEAD)
TF_SELECT="${TF_SELECT:-}"

# --- Revisions to compare (change detection only) ----------------------------------
if [ -z "$TF_SELECT" ]; then
  if [ "${EVENT:-}" = "pull_request" ]; then
    BASE_REV=$(git merge-base "origin/${BASE_REF:?BASE_REF is required for pull_request events}" HEAD)
  else
    BASE_REV="${BEFORE:-}"
    if [ -z "$BASE_REV" ] || [ "$BASE_REV" = "$ZERO_SHA" ] \
       || ! git cat-file -e "${BASE_REV}^{commit}" 2>/dev/null; then
      # Parent of the pushed commit; for the very first commit, the empty tree
      BASE_REV=$(git rev-parse --verify -q "${SHA:-HEAD}^" || git hash-object -t tree /dev/null)
    fi
  fi
  echo "Comparing ${BASE_REV} -> ${HEAD_REV}"
fi

# --- Helpers --------------------------------------------------------------------
# is_root REV DIR: DIR contains a .tf file with a backend block at REV
is_root() {
  git grep -qE "$BACKEND_RE" "$1" -- ":(glob)$2/*.tf" 2>/dev/null
}

# root_of REV PATH: nearest folder at or above PATH (within ROOTS_DIR) that is a root at REV
root_of() {
  local rev="$1" d
  d=$(dirname "$2")
  while [ "$d" = "$ROOTS_DIR" ] || [[ "$d" == "$ROOTS_DIR"/* ]]; do
    if is_root "$rev" "$d"; then echo "$d"; return 0; fi
    d=$(dirname "$d")
  done
  return 0
}

# all_roots REV: every root folder under ROOTS_DIR at REV
all_roots() {
  git grep -lE "$BACKEND_RE" "$1" -- ":(glob)$ROOTS_DIR/**/*.tf" 2>/dev/null \
    | while IFS= read -r line; do dirname "${line#*:}"; done
}

# load_modules REV DIR: sets MODS to the local module dirs called directly by DIR at REV
declare -A MOD_CACHE=()
MODS=""
load_modules() {
  local key="$1:$2"
  if [ -z "${MOD_CACHE[$key]+x}" ]; then
    MOD_CACHE[$key]=$(
      git grep -hE "$LOCAL_SRC_RE" "$1" -- ":(glob)$2/*.tf" 2>/dev/null \
        | sed -E 's/^[^"]*"([^"]+)".*/\1/' \
        | while IFS= read -r s; do realpath -m --relative-to="$PWD" "$2/$s"; done \
        | sort -u || true
    )
  fi
  MODS="${MOD_CACHE[$key]}"
}

# module_closure REV ROOT: every local module dir ROOT uses, including nested ones
module_closure() {
  local rev="$1" cur m
  local -A seen=()
  local queue=("$2")
  while ((${#queue[@]})); do
    cur="${queue[0]}"; queue=("${queue[@]:1}")
    load_modules "$rev" "$cur"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      [ -z "${seen[$m]:-}" ] || continue
      seen[$m]=1
      queue+=("$m")
    done <<<"$MODS"
  done
  [ "${#seen[@]}" -eq 0 ] || printf '%s\n' "${!seen[@]}"
}

# root_uses_changed ROOT: success if a changed file lies in a module ROOT uses
# (checked at both revisions, so removed module calls and deleted modules count)
root_uses_changed() {
  local root="$1" rev m p
  for rev in "$BASE_REV" "$HEAD_REV"; do
    is_root "$rev" "$root" || continue
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      for p in "${unmapped_paths[@]}"; do
        if [[ "$p" == "$m"/* ]]; then
          echo "  $root uses changed module: $m"
          return 0
        fi
      done
    done < <(module_closure "$rev" "$root")
  done
  return 1
}

# emit_matrix: writes the roots array as the job matrix and sets has_changes
emit_matrix() {
  local matrix dupes has_changes
  matrix=$(printf '%s\n' "${roots[@]}" | sort -u | jq -R -s -c '
    split("\n") | map(select(length > 0))
    | map({dir: ., name: (gsub("/"; "--") | gsub("[^A-Za-z0-9._-]"; "-"))})')

  # Artifact names must be unique per folder
  dupes=$(jq -r '[.[].name] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$matrix")
  if [ -n "$dupes" ]; then
    echo "::error::These folders map to the same artifact name; rename one of them: $dupes"
    exit 1
  fi

  has_changes=false
  [ "$matrix" != "[]" ] && has_changes=true

  echo "Terraform roots to plan: $matrix"
  {
    echo "matrix=$matrix"
    echo "has_changes=$has_changes"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

# --- Direct selection (recovery / drift) -----------------------------------------
roots=()
if [ -n "$TF_SELECT" ]; then
  if [ "$TF_SELECT" = "all" ]; then
    echo "Selecting ALL Terraform roots."
    while IFS= read -r r; do roots+=("$r"); done < <(all_roots "$HEAD_REV" | sort -u)
  else
    sel="${TF_SELECT%/}"
    if [[ "$sel" != "$ROOTS_DIR"/* ]] || [[ "$sel" == *..* ]] || ! is_root "$HEAD_REV" "$sel"; then
      echo "::error::'$TF_SELECT' is not a Terraform root (a folder under $ROOTS_DIR/ with a backend block)."
      exit 1
    fi
    echo "Selecting Terraform root: $sel"
    roots=("$sel")
  fi
  emit_matrix
  exit 0
fi

# --- Classify changed files -----------------------------------------------------
orphaned=()
unmapped_paths=()   # changed files that are not inside any root

while IFS=$'\t' read -r status path; do
  [ -n "$path" ] || continue
  [[ "$path" == *.md ]] && continue

  if [ "$status" = "D" ]; then
    old_root=$(root_of "$BASE_REV" "$path")
    if [ -z "$old_root" ]; then
      unmapped_paths+=("$path")
    elif is_root "$HEAD_REV" "$old_root"; then
      roots+=("$old_root")
    else
      orphaned+=("$old_root")
    fi
  else
    root=$(root_of "$HEAD_REV" "$path")
    if [ -n "$root" ]; then
      roots+=("$root")
    else
      unmapped_paths+=("$path")
    fi
  fi
done < <(git diff --name-status --no-renames "$BASE_REV" "$HEAD_REV")

if [ "${#orphaned[@]}" -gt 0 ]; then
  while IFS= read -r r; do
    echo "::error::Terraform root '$r' was removed, moved or renamed, or lost its backend block. Run terraform destroy (or migrate its state) first, then merge."
  done < <(printf '%s\n' "${orphaned[@]}" | sort -u)
  exit 1
fi

# --- Dependency-aware selection for files outside any root ------------------------
if [ "${#unmapped_paths[@]}" -gt 0 ]; then
  echo "Files outside any root changed. Selecting roots that use the changed modules."
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if root_uses_changed "$r"; then roots+=("$r"); fi
  done < <(all_roots "$HEAD_REV" | sort -u)
fi

# --- Build matrix ---------------------------------------------------------------
emit_matrix
