# lib/memory-sync.sh
# shellcheck shell=bash
# Sync host memory (Claude Code Auto Memory markdown) into the workspace
# container for a given run.

# shellcheck source=/dev/null
. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"

pal_memory_slug() {
    # Claude Code Auto Memory encodes a literal absolute path by replacing
    # every `/` with `-`. /home/jonny → -home-jonny.
    local path="$1"
    printf '%s\n' "${path//\//-}"
}
