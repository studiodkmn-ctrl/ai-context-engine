#!/usr/bin/env bash
# =============================================================================
# ai-bench.sh — duenner Wrapper um ai-bench.py (v9-d)
#
# Usage:
#   bash bench/ai-bench.sh [--model sonnet] [--tasks bench/tasks.yaml]
#                           [--out BENCHMARKS.md] [--repeat 1]
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/ai-bench.py" "$@"
