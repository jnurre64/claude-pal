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

# pal_memory_sync_to_container <host-repo-path> <container-workdir>
#
# One-way, read-only sync of Claude Code Auto Memory markdown from the host
# into the workspace container. Preserves subdir structure so the container's
# claude can auto-load MEMORY.md.
#
# *.jsonl transcripts are excluded by default (secret-tier). Set
# PAL_SYNC_TRANSCRIPTS=true to include them (not recommended).
pal_memory_sync_to_container() {
    local host_repo="$1"
    local container_workdir="$2"

    [ "${PAL_SYNC_MEMORIES:-true}" = "true" ] || return 0

    local host_slug container_slug host_dir container_dir
    host_slug="$(pal_memory_slug "$host_repo")"
    container_slug="$(pal_memory_slug "$container_workdir")"
    host_dir="${HOME}/.claude/projects/${host_slug}/memory"
    container_dir="/home/agent/.claude/projects/${container_slug}/memory"

    [ -d "$host_dir" ] || return 0

    docker exec "$PAL_WORKSPACE_NAME" \
        rm -rf "$container_dir" >/dev/null 2>&1 || true
    docker exec "$PAL_WORKSPACE_NAME" \
        mkdir -p "$container_dir" >/dev/null

    # Stage a filtered copy so the docker cp payload never contains *.jsonl
    # unless the user opted in.
    local staging
    staging="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$staging'" RETURN

    if [ "${PAL_SYNC_TRANSCRIPTS:-false}" = "true" ]; then
        cp -r "$host_dir/." "$staging/"
    else
        (
            cd "$host_dir" || exit 0
            find . -type f \! -name '*.jsonl' -print0 \
                | xargs -0 -I{} cp --parents {} "$staging/"
        )
    fi

    docker cp "$staging/." "${PAL_WORKSPACE_NAME}:${container_dir}"
}
