#!/usr/bin/env bash
# Switch this machine to your PERSONAL GitHub account.
# First run (or --setup) asks for username, email, and classic PAT.
#
#   ./switch-personal.sh
#   ./switch-personal.sh --setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/github-switch.sh"

switch_to_profile "personal" "${1:-}"
