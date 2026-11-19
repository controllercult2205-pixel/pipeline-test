#!/usr/bin/env bash
# terraform plan for one root. Run from the root folder.
#
# Never fails on the plan itself: the exit code is written to GITHUB_OUTPUT
# (exit_code: 0 = no changes, 1 = error, 2 = changes) and folder-status.sh
# decides. On changes, writes plan.txt and plan.json next to tfplan.
set -uo pipefail

terraform plan -detailed-exitcode -input=false -lock-timeout=5m -no-color -out=tfplan \
  > plan-output.txt 2>&1
plan_exit=$?

set -e
cat plan-output.txt
echo "exit_code=$plan_exit" >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [ "$plan_exit" -eq 2 ]; then
  terraform show -no-color tfplan > plan.txt
  terraform show -json tfplan > plan.json
fi
