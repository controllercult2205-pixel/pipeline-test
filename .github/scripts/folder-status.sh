#!/usr/bin/env bash
# Turns the outcomes of the plan job's steps into one folder status:
#   ready | no_changes | plan_failed | wiz_blocked | wiz_error
# Writes it as the "status" step output and to STATUS_FILE.
#
# Env in: INIT_OUT, FMT_OUT, VAL_OUT, PLAN_EXIT, WIZ_EXIT, STATUS_FILE
set -euo pipefail

status="plan_failed"
if [ "${INIT_OUT:-}" != "success" ] || [ "${FMT_OUT:-}" != "success" ] || [ "${VAL_OUT:-}" != "success" ]; then
  status="plan_failed"
elif [ "${PLAN_EXIT:-}" = "0" ]; then
  status="no_changes"
elif [ "${PLAN_EXIT:-}" = "2" ]; then
  if [ "${WIZ_EXIT:-}" = "0" ]; then
    status="ready"
  elif [ -n "${WIZ_EXIT:-}" ]; then
    status="wiz_blocked"
  else
    status="wiz_error"
  fi
fi

echo "Folder status: $status"
echo "status=$status" >> "$GITHUB_OUTPUT"
echo "$status" > "${STATUS_FILE:?STATUS_FILE is required}"
