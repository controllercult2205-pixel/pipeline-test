#!/usr/bin/env bash
# Writes the plan result for one Terraform root to the run summary.
#   PLAN_EXIT 0 -> "no changes"
#   PLAN_EXIT 2 -> "has changes", with plan.txt shown for reviewers
#   otherwise   -> "plan failed" (exits 1)
# With FAIL_ON_DRIFT=true (scheduled drift check), changes also exit 1 so the
# run fails and GitHub notifies.
#
# Run from the root folder. Env in: DIR, PLAN_EXIT, FAIL_ON_DRIFT
set -euo pipefail

dir="${DIR:?DIR is required}"
plan_exit="${PLAN_EXIT:-}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

case "$plan_exit" in
  0)
    echo "### ✅ \`$dir\`: no changes" >> "$summary"
    ;;
  2)
    {
      echo "### ⚠️ \`$dir\`: has changes (main and real infrastructure differ)"
      echo '```'
      cat plan.txt
      echo '```'
    } >> "$summary"
    if [ "${FAIL_ON_DRIFT:-false}" = "true" ]; then
      echo "::error::Drift detected in $dir. Run the recovery workflow for this folder."
      exit 1
    fi
    ;;
  *)
    echo "### ❌ \`$dir\`: plan failed" >> "$summary"
    echo "::error::terraform plan failed in $dir"
    exit 1
    ;;
esac
