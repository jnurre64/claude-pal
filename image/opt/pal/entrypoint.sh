#!/bin/bash
set -euo pipefail

# ─── Args: <event_type> <repo> <number> ─────────────────────────
EVENT_TYPE="${1:?Usage: entrypoint.sh <event_type> <repo> <number>}"
REPO="${2:?}"
NUMBER="${3:?}"

# ─── Status file path (bind-mounted from host) ──────────────────
STATUS_DIR="${PAL_STATUS_DIR:-/status}"
mkdir -p "$STATUS_DIR"

log() {
    printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$STATUS_DIR/log"
}

# ─── Placeholder for Phase 2: report a trivial success and exit ──
log "claude-pal entrypoint v0.1 (scaffold)"
log "EVENT_TYPE=$EVENT_TYPE REPO=$REPO NUMBER=$NUMBER"
log "Verifying claude CLI is present..."
claude --version | tee -a "$STATUS_DIR/log"
log "Verifying gh CLI is present..."
gh --version | tee -a "$STATUS_DIR/log"

cat > "$STATUS_DIR/status.json.tmp" <<EOF
{
  "phase": "complete",
  "outcome": "success",
  "failure_reason": null,
  "pr_number": null,
  "pr_url": null,
  "commits": [],
  "event_type": "$EVENT_TYPE",
  "repo": "$REPO",
  "number": $NUMBER
}
EOF
mv "$STATUS_DIR/status.json.tmp" "$STATUS_DIR/status.json"
log "Scaffold run complete."
