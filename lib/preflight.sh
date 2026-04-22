# lib/preflight.sh
# shellcheck shell=bash
# Preflight checks run before every dispatch.

pal_preflight_docker_reachable() {
    if ! docker info > /dev/null 2>&1; then
        local target="${DOCKER_HOST:-local}"
        echo "pal: ERROR — docker daemon not reachable (DOCKER_HOST=$target)" >&2
        return 1
    fi
}

pal_preflight_windows_bash() {
    local host_os
    host_os=$(uname -s)
    case "$host_os" in
        MINGW*|MSYS*|CYGWIN*)
            local bash_version
            bash_version=$(bash --version | head -1)
            if echo "$bash_version" | grep -qi wsl; then
                echo "pal: ERROR — Claude Code is using WSL's bash, not Git Bash" >&2
                echo "pal: Set CLAUDE_CODE_GIT_BASH_PATH in your Claude Code settings.json:" >&2
                printf 'pal:   {"env": {"CLAUDE_CODE_GIT_BASH_PATH": "C:\\\\Program Files\\\\Git\\\\bin\\\\bash.exe"}}\n' >&2
                return 1
            fi
            ;;
    esac
}

pal_preflight_gh_auth() {
    if ! GH_TOKEN="$GH_TOKEN" gh auth status > /dev/null 2>&1; then
        echo "pal: WARN — gh auth status failed with configured token" >&2
        # Non-fatal: some PATs return 200 but fail auth status; let the container try
    fi
}

pal_preflight_workspace_ready() {
    # shellcheck source=/dev/null
    . "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"
    if ! docker inspect "$PAL_WORKSPACE_NAME" >/dev/null 2>&1; then
        echo "preflight: workspace container ${PAL_WORKSPACE_NAME} not found — run /pal-setup first" >&2
        return 1
    fi
    pal_workspace_ensure_running
    if ! pal_workspace_is_authenticated; then
        echo "preflight: workspace not authenticated — run /pal-login" >&2
        return 1
    fi
}

pal_preflight_issue_not_in_flight() {
    local repo="$1"
    local number="$2"
    local lock
    lock="$(pal_runs_dir)/.lock-${repo//\//_}-${number}"
    if [ -f "$lock" ]; then
        local existing_run
        existing_run=$(cat "$lock")
        echo "pal: ERROR — another run is already in flight for $repo#$number (run $existing_run)" >&2
        echo "pal: Use '/pal-status $existing_run' to check its state, or '/pal-cancel $existing_run' to kill it" >&2
        return 1
    fi
}

pal_preflight_all() {
    local repo="${1:-}"
    local number="${2:-}"

    pal_load_config &&
    pal_preflight_docker_reachable &&
    pal_preflight_windows_bash &&
    pal_preflight_gh_auth &&
    pal_preflight_workspace_ready || return 1

    if [ -n "$repo" ] && [ -n "$number" ]; then
        pal_preflight_issue_not_in_flight "$repo" "$number" || return 1
    fi
}
