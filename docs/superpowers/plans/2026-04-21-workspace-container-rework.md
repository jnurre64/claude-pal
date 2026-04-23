# Workspace-Container Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sandbox-pal's ephemeral `docker run --rm` + `CLAUDE_CODE_OAUTH_TOKEN` env-passthrough model with a long-running workspace container that mints credentials via `claude /login` inside the container (Anthropic `.devcontainer` pattern). Drop the OAuth-token path entirely, add per-run host→container memory sync, add a managed container-level `CLAUDE.md`, and update all documentation.

**Architecture:** A single named container (`sandbox-pal-workspace`) is started once on `/pal-setup`, has credentials minted inside it via `/pal-login`, and keeps them in a Docker-managed named volume (`sandbox-pal-claude`). Every `pal-*` invocation auto-starts the workspace if stopped, then `docker exec`s in. The entrypoint splits: `workspace-boot.sh` (one-shot: firewall setup + `sleep infinity`) and `run-pipeline.sh` (per-run: clone + pipeline). Before each exec, the launcher syncs memory markdown from the host's `~/.claude/projects/<host-slug>/memory/` and a container-scoped CLAUDE.md (`~/.config/sandbox-pal/container-CLAUDE.md`) into the container.

**Tech Stack:** Bash, Docker CLI, Ubuntu 24.04 base, iptables + ipset firewall, BATS-Core for tests, `shellcheck` for lint. Claude Code plugin architecture with `${CLAUDE_PLUGIN_ROOT}`.

**Spec:** `docs/superpowers/specs/2026-04-21-sandbox-pal-auth-rework.md`

**Supersedes:** `docs/superpowers/plans/2026-04-18-sandbox-pal.md` (implementation details; pipeline contract and review-gate prompts stay).

---

## File Structure

### New files

- `lib/workspace.sh` — host-side workspace lifecycle: `pal_workspace_start`, `pal_workspace_stop`, `pal_workspace_restart`, `pal_workspace_status`, `pal_workspace_ensure_running`, `pal_workspace_is_authenticated`.
- `lib/memory-sync.sh` — host-side memory sync: `pal_memory_sync_to_container` (computes host and container slugs, rsyncs memory markdown excluding `*.jsonl`, preserves subdir).
- `lib/container-rules.sh` — host-side management of `~/.config/sandbox-pal/container-CLAUDE.md`: `pal_container_rules_path`, `pal_container_rules_ensure`, `pal_container_rules_sync_to_container`, `pal_container_rules_edit`.
- `image/opt/pal/workspace-boot.sh` — container-side one-shot boot: program firewall from `allowlist.yaml`, run verification assertion (deny works), then `sleep infinity`.
- `image/opt/pal/run-pipeline.sh` — container-side per-run pipeline: clone, fetch context, run review gates, implement, post-review, push, PR. (Factored from today's `entrypoint.sh`.)
- `skills/pal-workspace/SKILL.md` — operator skill: `start | stop | restart | status | edit-rules` subcommands.
- `skills/pal-login/SKILL.md` — runs `docker exec -it workspace claude /login` (interactive).
- `skills/pal-logout/SKILL.md` — `docker exec workspace rm -f /home/agent/.claude/.credentials.json`.
- `commands/pal-workspace.md`, `commands/pal-login.md`, `commands/pal-logout.md` — slash-command prompts for the above.
- `docs/authentication.md` — single source of truth for the new auth model; cross-links legal/compliance docs and Anthropic's reference `.devcontainer`.
- `tests/test_workspace_lifecycle.bats` — BATS for `lib/workspace.sh`.
- `tests/test_memory_sync.bats` — BATS for `lib/memory-sync.sh`.
- `tests/test_container_rules.bats` — BATS for `lib/container-rules.sh`.
- `tests/test_skill_pal_workspace.bats`, `tests/test_skill_pal_login.bats` — smoke tests for the new skills.

### Modified files

- `image/Dockerfile` — rebased on Anthropic-devcontainer layout: non-root `agent` user, named-volume mount point at `/home/agent/.claude/`, minimal default-deny firewall setup. Keep `CMD` overridable; default to `/opt/pal/workspace-boot.sh`.
- `image/opt/pal/entrypoint.sh` — **deleted** (replaced by `workspace-boot.sh` + `run-pipeline.sh`).
- `image/opt/pal/lib/firewall.sh` — minor: called once from `workspace-boot.sh`; add the Anthropic-style "try reaching non-allowlisted host, assert fails" verification step; move re-resolution of `allowlist.yaml` to boot time.
- `lib/config.sh` — drop `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` checks. Keep `GH_TOKEN`. Add optional reads for `PAL_SYNC_MEMORIES`, `PAL_SYNC_TRANSCRIPTS`, `PAL_CPUS`, `PAL_MEMORY` from `~/.config/sandbox-pal/config.env`.
- `lib/preflight.sh` — replace `pal_preflight_single_auth_method` with `pal_preflight_workspace_ready` (workspace container exists, is running or can auto-start, and `/home/agent/.claude/.credentials.json` exists inside).
- `lib/launcher.sh` — switch `pal_launch_sync` / `pal_launch_async` from `docker run --rm` to `docker exec` against the workspace container; memory + rules sync before exec; remove Claude env-var forwarding; keep `GH_TOKEN` and `AGENT_*` env vars.
- `skills/pal-implement/SKILL.md`, `skills/pal-revise/SKILL.md` — source `lib/workspace.sh`, `lib/memory-sync.sh`, `lib/container-rules.sh`; call `pal_workspace_ensure_running`, sync memory + rules, then launch.
- `skills/pal-cancel/SKILL.md`, `skills/pal-status/SKILL.md`, `skills/pal-logs/SKILL.md`, `skills/pal-plan/SKILL.md` — minor: ensure workspace assumptions documented; no behavior change for plan.
- `commands/pal-setup.md` — rewrite: pull image → create volume → start workspace → guide user to `/pal-login`.
- `commands/pal-brainstorm.md` — verify no stale `setup-token` references.
- `README.md` — rewrite Authentication, Getting started, Per-repo config sections.
- `CLAUDE.md` (project root) — rewrite the "Authentication model" paragraph.
- `UPSTREAM.md` — unchanged content, but verify no stale references.
- `CHANGELOG.md` — minor-version bump entry (`0.X` → `0.(X+1)`).
- `docs/install.md` — rewrite to match new flow.
- `docs/superpowers/plans/2026-04-18-sandbox-pal.md` — add a `superseded_by` note at the top.
- `docs/superpowers/specs/2026-04-18-sandbox-pal-design.md` — insert inline "SUPERSEDED BY 2026-04-21 rework" markers at §3, §5.2, §5.6, §6.1, §6.2, §9.3 with a pointer to the new spec.

---

## Phase Overview

1. **Base image + boot split** — Dockerfile rework, workspace-boot.sh, run-pipeline.sh, firewall verification.
2. **Host-side lifecycle library** — `lib/workspace.sh` with start/stop/restart/status/ensure-running/is-authenticated.
3. **Config + preflight rework** — drop Claude env-var auth from `lib/config.sh`; replace auth preflight with workspace-ready preflight.
4. **Memory sync library** — `lib/memory-sync.sh`, host-slug / container-slug computation, `*.jsonl` exclusion.
5. **Container-rules library** — `lib/container-rules.sh`, manages `~/.config/sandbox-pal/container-CLAUDE.md`.
6. **Launcher rework** — switch from `docker run --rm` to `docker exec`; memory + rules sync before exec.
7. **Skills: pal-workspace, pal-login, pal-logout** — new operator skills.
8. **Skills: pal-setup rewrite** — new setup flow.
9. **Skills: pal-implement, pal-revise updates** — wire in ensure-running + sync.
10. **Documentation update phase** — CLAUDE.md, README.md, install.md, new authentication.md, SKILL.md files, CHANGELOG, supersede markers.
11. **Version bump + merge prep.**

Each phase ends at a demoable / testable milestone. Every non-trivial change uses TDD: write failing test → run it fails → minimal impl → run it passes → commit.

---

## Phase 1: Base image + boot split

### Task 1.1: Add BATS fixture for a fake `docker` binary

**Files:**
- Create: `tests/test_helper/fake-docker.sh`

- [ ] **Step 1: Write the helper**

```bash
# tests/test_helper/fake-docker.sh
# shellcheck shell=bash
# Provide a `docker` shim on PATH that records invocations to a file.
# Tests can inspect FAKE_DOCKER_LOG and can set FAKE_DOCKER_STATE to
# control responses to `docker ps`, `docker inspect`, etc.

fake_docker_setup() {
    FAKE_DOCKER_DIR="$(mktemp -d)"
    FAKE_DOCKER_LOG="$FAKE_DOCKER_DIR/calls.log"
    FAKE_DOCKER_STATE="$FAKE_DOCKER_DIR/state"
    mkdir -p "$FAKE_DOCKER_STATE"
    : > "$FAKE_DOCKER_LOG"

    cat > "$FAKE_DOCKER_DIR/docker" <<'SHIM'
#!/usr/bin/env bash
set -u
echo "$*" >> "$FAKE_DOCKER_LOG"
case "$1" in
    ps)
        if [ -f "$FAKE_DOCKER_STATE/running" ]; then
            echo "sandbox-pal-workspace"
        fi
        ;;
    inspect)
        if [ -f "$FAKE_DOCKER_STATE/exists" ]; then
            echo '{"State":{"Status":"running"}}'
            exit 0
        fi
        exit 1
        ;;
    exec)
        # Last arg is usually the command; simulate success by default.
        if [ -f "$FAKE_DOCKER_STATE/exec_fails" ]; then
            exit 1
        fi
        ;;
    run|start|stop|rm|cp|volume|pull)
        : # success
        ;;
    *)
        : # success
        ;;
esac
exit 0
SHIM
    chmod +x "$FAKE_DOCKER_DIR/docker"
    export PATH="$FAKE_DOCKER_DIR:$PATH"
    export FAKE_DOCKER_LOG FAKE_DOCKER_STATE
}

fake_docker_teardown() {
    rm -rf "$FAKE_DOCKER_DIR"
}

fake_docker_set_running() {
    : > "$FAKE_DOCKER_STATE/running"
    : > "$FAKE_DOCKER_STATE/exists"
}

fake_docker_set_stopped() {
    rm -f "$FAKE_DOCKER_STATE/running"
    : > "$FAKE_DOCKER_STATE/exists"
}

fake_docker_set_absent() {
    rm -f "$FAKE_DOCKER_STATE/running" "$FAKE_DOCKER_STATE/exists"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_helper/fake-docker.sh
git commit -m "test: add fake docker shim for workspace-lifecycle tests"
```

### Task 1.2: Image smoke test asserts workspace-boot.sh exists

**Files:**
- Modify: `tests/test_image_smoke.bats`

- [ ] **Step 1: Read the current test to see the existing pattern**

Run: `cat tests/test_image_smoke.bats`
Observe conventions (REPO_ROOT, image tag, `run docker run ...`).

- [ ] **Step 2: Add a failing test for workspace-boot.sh**

Append to `tests/test_image_smoke.bats`:

```bash
@test "image contains workspace-boot.sh and run-pipeline.sh" {
    run docker run --rm --entrypoint sh "$IMAGE_TAG" -c 'test -x /opt/pal/workspace-boot.sh && test -x /opt/pal/run-pipeline.sh'
    [ "$status" -eq 0 ]
}

@test "image default CMD is workspace-boot.sh" {
    run docker inspect --format '{{json .Config.Cmd}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workspace-boot.sh"* ]]
}
```

- [ ] **Step 3: Run the test, confirm it fails**

Run: `bats tests/test_image_smoke.bats -f "workspace-boot"`
Expected: FAIL (scripts don't exist yet).

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/test_image_smoke.bats
git commit -m "test: assert workspace-boot.sh and run-pipeline.sh in image (failing)"
```

### Task 1.3: Split entrypoint.sh — extract run-pipeline.sh

**Files:**
- Create: `image/opt/pal/run-pipeline.sh` (factored from current `entrypoint.sh` — everything from `EVENT_TYPE` branching through `push + PR`)
- Modify: `image/opt/pal/entrypoint.sh` (will be deleted after the split lands; left in place as a thin shim for now)

- [ ] **Step 1: Read the current entrypoint**

Run: `cat image/opt/pal/entrypoint.sh | head -60`

Identify two regions:
- **Boot region**: firewall setup (`. /opt/pal/lib/firewall.sh; apply_firewall ...`).
- **Pipeline region**: clone, fetch context, review gates, claude invocation, commit, push, PR.

- [ ] **Step 2: Create run-pipeline.sh with the pipeline region**

```bash
#!/usr/bin/env bash
# image/opt/pal/run-pipeline.sh
# Per-run pipeline. Invoked via `docker exec` against a long-running workspace
# container. Expects firewall already programmed by workspace-boot.sh.
#
# Usage: run-pipeline.sh <event-type> <repo> <number>
#   event-type ∈ {implement, revise}
#   repo       = owner/name
#   number     = issue or PR number
#
# Reads from environment (set at exec time):
#   GH_TOKEN, AGENT_TEST_COMMAND, AGENT_TEST_SETUP_COMMAND,
#   AGENT_ALLOWED_TOOLS_*, AGENT_MODEL_*, PAL_ALLOWLIST_EXTRA_DOMAINS.

set -euo pipefail

EVENT_TYPE="${1:?event type required}"
REPO="${2:?repo required}"
NUMBER="${3:?issue/PR number required}"

RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
WORK_DIR="/home/agent/work/${RUN_ID}"
STATUS_DIR="/status/${RUN_ID}"

. /opt/pal/lib/worktree.sh
. /opt/pal/lib/fetch-context.sh
. /opt/pal/lib/review-gates.sh
. /opt/pal/lib/claude-runner.sh

mkdir -p "$WORK_DIR" "$STATUS_DIR"
trap 'rm -rf "$WORK_DIR" /home/agent/.claude/projects/-home-agent-work-'"$RUN_ID"'' EXIT

# If allowlist extras differ from workspace default, reload firewall.
if [ -n "${PAL_ALLOWLIST_EXTRA_DOMAINS:-}" ]; then
    . /opt/pal/lib/firewall.sh
    refresh_firewall_for "$PAL_ALLOWLIST_EXTRA_DOMAINS"
fi

# (… remainder: copied verbatim from today's entrypoint.sh, starting from the
# post-firewall block. The exact body is in entrypoint.sh today; move, don't
# rewrite.)
```

(Full body: move lines from current `entrypoint.sh` starting immediately after the firewall-apply block. No behavior changes.)

- [ ] **Step 3: Mark the script executable**

Run: `chmod +x image/opt/pal/run-pipeline.sh`

- [ ] **Step 4: Commit**

```bash
git add image/opt/pal/run-pipeline.sh
git commit -m "feat(image): factor pipeline out of entrypoint.sh into run-pipeline.sh"
```

### Task 1.4: Create workspace-boot.sh

**Files:**
- Create: `image/opt/pal/workspace-boot.sh`

- [ ] **Step 1: Write the boot script**

```bash
#!/usr/bin/env bash
# image/opt/pal/workspace-boot.sh
# One-shot boot for the workspace container. Programs the firewall once, runs
# the default-deny verification, then sleeps forever. `docker exec` is the
# per-run entry point.

set -euo pipefail

. /opt/pal/lib/firewall.sh

echo "pal: programming firewall from /opt/pal/allowlist.yaml"
apply_firewall /opt/pal/allowlist.yaml

echo "pal: verifying default-deny (attempting to reach example.com)"
if curl --max-time 3 --silent --output /dev/null https://example.com; then
    echo "pal: FATAL: firewall verification failed — example.com reachable" >&2
    exit 1
fi
echo "pal: firewall verified (example.com unreachable as expected)"

echo "pal: workspace ready — sleeping forever, awaiting docker exec"
exec sleep infinity
```

- [ ] **Step 2: Mark executable**

Run: `chmod +x image/opt/pal/workspace-boot.sh`

- [ ] **Step 3: Commit**

```bash
git add image/opt/pal/workspace-boot.sh
git commit -m "feat(image): add workspace-boot.sh for long-lived workspace container"
```

### Task 1.5: Rework Dockerfile to Anthropic devcontainer layout

**Files:**
- Modify: `image/Dockerfile`

- [ ] **Step 1: Read current Dockerfile**

Run: `cat image/Dockerfile`

- [ ] **Step 2: Rewrite with non-root `agent` user, volume mount point, new default CMD**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg iptables ipset jq sudo \
        unzip zip bash less man-db procps \
    && rm -rf /var/lib/apt/lists/*

# gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# claude CLI (native binary installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Non-root agent user. UID 1000 matches typical host users but is not required
# (named volume owns its permissions).
RUN useradd --create-home --shell /bin/bash --uid 1000 agent \
    && mkdir -p /home/agent/.claude /home/agent/work /status \
    && chown -R agent:agent /home/agent /status

# Firewall caps are granted at `docker run --cap-add NET_ADMIN --cap-add NET_RAW`
# time; we still need sudo here so workspace-boot.sh can program iptables.
RUN echo "agent ALL=(root) NOPASSWD: /usr/sbin/iptables, /usr/sbin/ip6tables, /usr/sbin/ipset, /bin/cp" \
        > /etc/sudoers.d/10-agent-firewall \
    && chmod 0440 /etc/sudoers.d/10-agent-firewall

COPY --chown=agent:agent image/opt/pal/ /opt/pal/
RUN chmod +x /opt/pal/workspace-boot.sh /opt/pal/run-pipeline.sh \
    && find /opt/pal/lib -name '*.sh' -exec chmod +x {} +

USER agent
WORKDIR /home/agent
VOLUME ["/home/agent/.claude"]

CMD ["/opt/pal/workspace-boot.sh"]
```

- [ ] **Step 3: Build the image locally**

Run: `docker build -t sandbox-pal:dev -f image/Dockerfile .`
Expected: build succeeds.

- [ ] **Step 4: Run the image-smoke test from Task 1.2**

Run: `IMAGE_TAG=sandbox-pal:dev bats tests/test_image_smoke.bats`
Expected: previously failing `workspace-boot` tests now pass. Other image tests still pass.

- [ ] **Step 5: Delete the old entrypoint.sh**

Run: `git rm image/opt/pal/entrypoint.sh`

- [ ] **Step 6: Commit**

```bash
git add image/Dockerfile
git commit -m "feat(image): rebase Dockerfile on Anthropic devcontainer pattern (agent user, named volume, split entrypoint)"
```

### Task 1.6: Add firewall verification step to firewall.sh

**Files:**
- Modify: `image/opt/pal/lib/firewall.sh`

- [ ] **Step 1: Read current firewall.sh**

Run: `cat image/opt/pal/lib/firewall.sh`

- [ ] **Step 2: Add verification function**

Append:

```bash
# verify_firewall_deny — assert a non-allowlisted host is unreachable.
# Used by workspace-boot.sh as a safety check.
verify_firewall_deny() {
    local probe_host="${1:-example.com}"
    if curl --max-time 3 --silent --output /dev/null "https://${probe_host}"; then
        echo "firewall: verification FAILED — ${probe_host} reachable" >&2
        return 1
    fi
    return 0
}
```

(Then update `workspace-boot.sh` to call `verify_firewall_deny` instead of inlining the curl.)

- [ ] **Step 3: Commit**

```bash
git add image/opt/pal/lib/firewall.sh image/opt/pal/workspace-boot.sh
git commit -m "feat(image): add firewall deny verification step"
```

---

## Phase 2: Host-side workspace lifecycle library

### Task 2.1: Write failing test for `pal_workspace_start` (fresh workspace)

**Files:**
- Create: `tests/test_workspace_lifecycle.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# shellcheck shell=bash

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/fake-docker.sh'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
    fake_docker_setup
    # shellcheck source=../lib/workspace.sh
    . "$REPO_ROOT/lib/workspace.sh"
}

teardown() {
    fake_docker_teardown
}

@test "pal_workspace_start creates volume and runs container when absent" {
    fake_docker_set_absent
    run pal_workspace_start
    assert_success
    run grep "volume create sandbox-pal-claude" "$FAKE_DOCKER_LOG"
    assert_success
    run grep "run -d --name sandbox-pal-workspace" "$FAKE_DOCKER_LOG"
    assert_success
    run grep "cap-add NET_ADMIN" "$FAKE_DOCKER_LOG"
    assert_success
    run grep "cap-add NET_RAW" "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_workspace_start is a no-op if already running" {
    fake_docker_set_running
    run pal_workspace_start
    assert_success
    run grep "run -d" "$FAKE_DOCKER_LOG"
    assert_failure
}

@test "pal_workspace_start starts existing but stopped container" {
    fake_docker_set_stopped
    run pal_workspace_start
    assert_success
    run grep "^start sandbox-pal-workspace" "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_workspace_start respects PAL_CPUS and PAL_MEMORY" {
    fake_docker_set_absent
    PAL_CPUS=2.0 PAL_MEMORY=4g run pal_workspace_start
    assert_success
    run grep -- "--cpus=2.0" "$FAKE_DOCKER_LOG"
    assert_success
    run grep -- "--memory=4g" "$FAKE_DOCKER_LOG"
    assert_success
}
```

- [ ] **Step 2: Run, confirm all fail**

Run: `bats tests/test_workspace_lifecycle.bats`
Expected: FAIL — `lib/workspace.sh` doesn't exist.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_workspace_lifecycle.bats
git commit -m "test: add lifecycle tests for pal_workspace_start (failing)"
```

### Task 2.2: Implement `pal_workspace_start`

**Files:**
- Create: `lib/workspace.sh`

- [ ] **Step 1: Write the initial library**

```bash
# lib/workspace.sh
# shellcheck shell=bash
# Host-side lifecycle for the long-running sandbox-pal workspace container.

: "${PAL_WORKSPACE_NAME:=sandbox-pal-workspace}"
: "${PAL_WORKSPACE_VOLUME:=sandbox-pal-claude}"
: "${PAL_WORKSPACE_IMAGE:=sandbox-pal:latest}"

_pal_workspace_exists() {
    docker inspect "$PAL_WORKSPACE_NAME" >/dev/null 2>&1
}

_pal_workspace_is_running() {
    docker ps --format '{{.Names}}' | grep -Fxq "$PAL_WORKSPACE_NAME"
}

pal_workspace_start() {
    if _pal_workspace_is_running; then
        return 0
    fi
    if _pal_workspace_exists; then
        docker start "$PAL_WORKSPACE_NAME" >/dev/null
        return 0
    fi
    docker volume create "$PAL_WORKSPACE_VOLUME" >/dev/null

    local -a args=(
        run -d
        --name "$PAL_WORKSPACE_NAME"
        --cap-add NET_ADMIN
        --cap-add NET_RAW
        -v "${PAL_WORKSPACE_VOLUME}:/home/agent/.claude"
    )
    [ -n "${PAL_CPUS:-}" ]   && args+=(--cpus="$PAL_CPUS")
    [ -n "${PAL_MEMORY:-}" ] && args+=(--memory="$PAL_MEMORY")
    args+=("$PAL_WORKSPACE_IMAGE" /opt/pal/workspace-boot.sh)

    docker "${args[@]}" >/dev/null
}
```

- [ ] **Step 2: Run tests**

Run: `bats tests/test_workspace_lifecycle.bats`
Expected: Task 2.1 tests pass.

- [ ] **Step 3: shellcheck**

Run: `shellcheck lib/workspace.sh`
Expected: no warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/workspace.sh
git commit -m "feat(lib): add pal_workspace_start with cpu/memory caps"
```

### Task 2.3: Write failing tests for stop/restart/status/ensure-running/is-authenticated

**Files:**
- Modify: `tests/test_workspace_lifecycle.bats`

- [ ] **Step 1: Append tests**

```bash
@test "pal_workspace_stop stops running workspace" {
    fake_docker_set_running
    run pal_workspace_stop
    assert_success
    run grep "^stop sandbox-pal-workspace" "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_workspace_stop is a no-op if not running" {
    fake_docker_set_stopped
    run pal_workspace_stop
    assert_success
    run grep "^stop " "$FAKE_DOCKER_LOG"
    assert_failure
}

@test "pal_workspace_restart stops then starts" {
    fake_docker_set_running
    run pal_workspace_restart
    assert_success
    run grep "^stop sandbox-pal-workspace" "$FAKE_DOCKER_LOG"
    assert_success
    run grep "^start sandbox-pal-workspace" "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_workspace_ensure_running starts stopped workspace and emits log line" {
    fake_docker_set_stopped
    run pal_workspace_ensure_running
    assert_success
    assert_output --partial "workspace stopped — starting"
}

@test "pal_workspace_ensure_running is silent when already running" {
    fake_docker_set_running
    run pal_workspace_ensure_running
    assert_success
    refute_output --partial "workspace stopped"
}

@test "pal_workspace_is_authenticated returns 0 when credentials exist" {
    fake_docker_set_running
    # fake docker defaults to exit 0 for exec
    run pal_workspace_is_authenticated
    assert_success
}

@test "pal_workspace_is_authenticated returns non-zero when credentials missing" {
    fake_docker_set_running
    : > "$FAKE_DOCKER_STATE/exec_fails"
    run pal_workspace_is_authenticated
    assert_failure
}

@test "pal_workspace_status prints name, state, and auth summary" {
    fake_docker_set_running
    run pal_workspace_status
    assert_success
    assert_output --partial "sandbox-pal-workspace"
    assert_output --partial "running"
}
```

- [ ] **Step 2: Run, confirm failures**

Run: `bats tests/test_workspace_lifecycle.bats`

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_workspace_lifecycle.bats
git commit -m "test: add lifecycle tests for stop/restart/status/ensure-running/is-authenticated (failing)"
```

### Task 2.4: Implement stop/restart/status/ensure-running/is-authenticated

**Files:**
- Modify: `lib/workspace.sh`

- [ ] **Step 1: Extend the library**

```bash
pal_workspace_stop() {
    if _pal_workspace_is_running; then
        docker stop "$PAL_WORKSPACE_NAME" >/dev/null
    fi
}

pal_workspace_restart() {
    pal_workspace_stop
    pal_workspace_start
}

pal_workspace_ensure_running() {
    if _pal_workspace_is_running; then
        return 0
    fi
    echo "pal: workspace stopped — starting…" >&2
    pal_workspace_start
}

pal_workspace_is_authenticated() {
    docker exec "$PAL_WORKSPACE_NAME" \
        test -f /home/agent/.claude/.credentials.json
}

pal_workspace_status() {
    if ! _pal_workspace_exists; then
        echo "workspace: absent (no container named ${PAL_WORKSPACE_NAME})"
        return 0
    fi
    local state
    state="$(docker inspect --format '{{.State.Status}}' "$PAL_WORKSPACE_NAME" 2>/dev/null || echo unknown)"
    echo "workspace: ${PAL_WORKSPACE_NAME} (${state})"
    if [ "$state" = "running" ]; then
        if pal_workspace_is_authenticated; then
            echo "  auth: present"
        else
            echo "  auth: missing — run /pal-login"
        fi
    fi
}
```

- [ ] **Step 2: Run all lifecycle tests**

Run: `bats tests/test_workspace_lifecycle.bats`
Expected: all green.

- [ ] **Step 3: shellcheck**

Run: `shellcheck lib/workspace.sh`

- [ ] **Step 4: Commit**

```bash
git add lib/workspace.sh
git commit -m "feat(lib): add workspace stop/restart/status/ensure-running/is-authenticated"
```

---

## Phase 3: Config + preflight rework

### Task 3.1: Failing test — config drops Claude env-var checks and reads knobs from config.env

**Files:**
- Create or modify: `tests/test_config.bats`

- [ ] **Step 1: Write/append tests**

```bash
@test "pal_load_config succeeds when only GH_TOKEN is set (OAuth no longer required)" {
    unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
    export GH_TOKEN=ghp_test
    run pal_load_config
    assert_success
}

@test "pal_load_config errors only on missing GH_TOKEN" {
    unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY GH_TOKEN GITHUB_TOKEN
    run pal_load_config
    assert_failure
    assert_output --partial "GH_TOKEN"
    refute_output --partial "CLAUDE_CODE_OAUTH_TOKEN"
}

@test "pal_load_config sources ~/.config/sandbox-pal/config.env when present" {
    export HOME="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.config/sandbox-pal"
    cat > "$HOME/.config/sandbox-pal/config.env" <<EOF
PAL_CPUS=2.0
PAL_MEMORY=4g
PAL_SYNC_MEMORIES=false
EOF
    export GH_TOKEN=ghp_test
    run bash -c '. "$CLAUDE_PLUGIN_ROOT/lib/config.sh" && pal_load_config && echo "CPUS=$PAL_CPUS MEM=$PAL_MEMORY SYNC=$PAL_SYNC_MEMORIES"'
    assert_success
    assert_output --partial "CPUS=2.0"
    assert_output --partial "MEM=4g"
    assert_output --partial "SYNC=false"
}
```

- [ ] **Step 2: Run, confirm failures**

Run: `bats tests/test_config.bats`

- [ ] **Step 3: Commit**

```bash
git add tests/test_config.bats
git commit -m "test: config drops Claude env vars and reads config.env knobs (failing)"
```

### Task 3.2: Rewrite `lib/config.sh`

**Files:**
- Modify: `lib/config.sh`

- [ ] **Step 1: Replace the file**

```bash
# lib/config.sh
# shellcheck shell=bash
# sandbox-pal host-side config loader.
#
# Credentials: GH_TOKEN (required) is env-passthrough. Claude credentials are
# NOT env-passthrough — they are minted inside the workspace container via
# `claude /login`, persisted in the named volume `sandbox-pal-claude`, and
# never touch the host shell.
#
# Optional non-secret knobs live in ~/.config/sandbox-pal/config.env:
#   PAL_SYNC_MEMORIES     (default true)
#   PAL_SYNC_TRANSCRIPTS  (default false — *.jsonl are secret-tier)
#   PAL_CPUS              (default unset = uncapped)
#   PAL_MEMORY            (default unset = uncapped)

pal_load_config() {
    GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sandbox-pal/config.env"
    if [ -f "$cfg" ]; then
        # shellcheck disable=SC1090
        . "$cfg"
    fi

    : "${PAL_SYNC_MEMORIES:=true}"
    : "${PAL_SYNC_TRANSCRIPTS:=false}"
    export PAL_SYNC_MEMORIES PAL_SYNC_TRANSCRIPTS
    [ -n "${PAL_CPUS:-}" ]   && export PAL_CPUS
    [ -n "${PAL_MEMORY:-}" ] && export PAL_MEMORY

    if [ -z "${GH_TOKEN:-}" ]; then
        cat >&2 <<'EOF'
pal: missing required environment variable: GH_TOKEN

pal: one-time setup (bash/zsh):
pal:   echo 'export GH_TOKEN=github_pat_<token>' >> ~/.bashrc
pal:   source ~/.bashrc

pal: Claude credentials are handled by the workspace container (not an env var).
pal: After GH_TOKEN is set, run:
pal:   /pal-setup   # create workspace
pal:   /pal-login   # mint credentials inside the container
EOF
        return 1
    fi
}
```

- [ ] **Step 2: Run tests**

Run: `bats tests/test_config.bats`
Expected: all pass.

- [ ] **Step 3: shellcheck**

Run: `shellcheck lib/config.sh`

- [ ] **Step 4: Commit**

```bash
git add lib/config.sh
git commit -m "feat(lib): drop Claude env-var auth from config; read new knobs from config.env"
```

### Task 3.3: Failing test — preflight checks workspace readiness instead of auth method

**Files:**
- Modify: `tests/test_preflight.bats` (create if absent)

- [ ] **Step 1: Write tests**

```bash
@test "pal_preflight_workspace_ready fails when workspace absent" {
    fake_docker_set_absent
    run pal_preflight_workspace_ready
    assert_failure
    assert_output --partial "workspace"
}

@test "pal_preflight_workspace_ready fails when running but not authenticated" {
    fake_docker_set_running
    : > "$FAKE_DOCKER_STATE/exec_fails"
    run pal_preflight_workspace_ready
    assert_failure
    assert_output --partial "/pal-login"
}

@test "pal_preflight_workspace_ready succeeds when running and authenticated" {
    fake_docker_set_running
    run pal_preflight_workspace_ready
    assert_success
}
```

- [ ] **Step 2: Run, confirm failures**

Run: `bats tests/test_preflight.bats`

- [ ] **Step 3: Commit**

```bash
git add tests/test_preflight.bats
git commit -m "test: preflight checks workspace-ready (failing)"
```

### Task 3.4: Rewrite `pal_preflight_single_auth_method` as `pal_preflight_workspace_ready`

**Files:**
- Modify: `lib/preflight.sh`

- [ ] **Step 1: Remove `pal_preflight_single_auth_method` and add `pal_preflight_workspace_ready`**

```bash
pal_preflight_workspace_ready() {
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
```

Update `pal_preflight_all` to call `pal_preflight_workspace_ready` in place of the removed auth-method preflight.

- [ ] **Step 2: Run preflight tests**

Run: `bats tests/test_preflight.bats`
Expected: pass.

- [ ] **Step 3: Run full test suite for regressions**

Run: `bats tests/`

- [ ] **Step 4: Commit**

```bash
git add lib/preflight.sh
git commit -m "feat(lib): replace auth-method preflight with workspace-ready check"
```

---

## Phase 4: Memory sync library

### Task 4.1: Failing test — slug encoding

**Files:**
- Create: `tests/test_memory_sync.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats
# shellcheck shell=bash

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/fake-docker.sh'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
    fake_docker_setup
    # shellcheck source=../lib/memory-sync.sh
    . "$REPO_ROOT/lib/memory-sync.sh"
}

teardown() {
    fake_docker_teardown
}

@test "pal_memory_slug encodes / as -" {
    run pal_memory_slug /home/jonny/repos/sandbox-pal
    assert_success
    assert_output "-home-jonny-repos-sandbox-pal"
}

@test "pal_memory_slug encodes nested path" {
    run pal_memory_slug /home/agent/work/run-42
    assert_success
    assert_output "-home-agent-work-run-42"
}
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Commit**

```bash
git add tests/test_memory_sync.bats
git commit -m "test: pal_memory_slug encoding (failing)"
```

### Task 4.2: Implement `pal_memory_slug`

**Files:**
- Create: `lib/memory-sync.sh`

- [ ] **Step 1: Write initial library**

```bash
# lib/memory-sync.sh
# shellcheck shell=bash
# Sync host memory (Claude Code Auto Memory markdown) into the workspace
# container for a given run.

. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"

pal_memory_slug() {
    # Claude Code Auto Memory encodes a literal absolute path by replacing
    # every `/` with `-`. /home/jonny → -home-jonny.
    local path="$1"
    printf '%s\n' "${path//\//-}"
}
```

- [ ] **Step 2: Run tests**

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add lib/memory-sync.sh
git commit -m "feat(lib): add pal_memory_slug host-path encoder"
```

### Task 4.3: Failing test — sync copies markdown, excludes jsonl

**Files:**
- Modify: `tests/test_memory_sync.bats`

- [ ] **Step 1: Append tests**

```bash
@test "pal_memory_sync_to_container copies MEMORY.md and topic .md files" {
    fake_docker_set_running

    local host_proj="$BATS_TEST_TMPDIR/host/.claude/projects/-home-me-repos-foo/memory"
    mkdir -p "$host_proj"
    echo "# index" > "$host_proj/MEMORY.md"
    echo "# topic" > "$host_proj/user_role.md"
    echo '{"secret":1}' > "$host_proj/session.jsonl"

    HOME="$BATS_TEST_TMPDIR/host" \
    PAL_SYNC_MEMORIES=true \
        run pal_memory_sync_to_container \
            /home/me/repos/foo \
            /home/agent/work/run-1
    assert_success

    # Assert the docker cp/exec commands were called and *.jsonl is NOT in the
    # payload (inspect FAKE_DOCKER_LOG).
    run grep -E 'exec.*rm -rf /home/agent/.claude/projects/-home-agent-work-run-1/memory' "$FAKE_DOCKER_LOG"
    assert_success
    run grep -E 'cp .* sandbox-pal-workspace:/home/agent/.claude/projects/-home-agent-work-run-1/memory' "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_memory_sync_to_container is a no-op when PAL_SYNC_MEMORIES=false" {
    fake_docker_set_running
    PAL_SYNC_MEMORIES=false run pal_memory_sync_to_container /any /any
    assert_success
    run grep "^cp " "$FAKE_DOCKER_LOG"
    assert_failure
}

@test "pal_memory_sync_to_container does nothing if host memory dir absent" {
    fake_docker_set_running
    HOME="$BATS_TEST_TMPDIR/empty" run pal_memory_sync_to_container /nope /home/agent/work/run-1
    assert_success
}
```

- [ ] **Step 2: Run, confirm failures**

- [ ] **Step 3: Commit**

```bash
git add tests/test_memory_sync.bats
git commit -m "test: pal_memory_sync_to_container copy + exclusion behavior (failing)"
```

### Task 4.4: Implement `pal_memory_sync_to_container`

**Files:**
- Modify: `lib/memory-sync.sh`

- [ ] **Step 1: Extend**

```bash
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
```

- [ ] **Step 2: Run tests**

Run: `bats tests/test_memory_sync.bats`
Expected: pass.

- [ ] **Step 3: shellcheck**

- [ ] **Step 4: Commit**

```bash
git add lib/memory-sync.sh
git commit -m "feat(lib): add pal_memory_sync_to_container with jsonl exclusion"
```

---

## Phase 5: Container-rules library

### Task 5.1: Failing test — ensure + sync rules file

**Files:**
- Create: `tests/test_container_rules.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats
# shellcheck shell=bash

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/fake-docker.sh'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    fake_docker_setup
    # shellcheck source=../lib/container-rules.sh
    . "$REPO_ROOT/lib/container-rules.sh"
}

teardown() {
    fake_docker_teardown
}

@test "pal_container_rules_path respects XDG_CONFIG_HOME" {
    XDG_CONFIG_HOME="$HOME/xdg" run pal_container_rules_path
    assert_success
    assert_output "$HOME/xdg/sandbox-pal/container-CLAUDE.md"
}

@test "pal_container_rules_path falls back to ~/.config" {
    unset XDG_CONFIG_HOME
    run pal_container_rules_path
    assert_success
    assert_output "$HOME/.config/sandbox-pal/container-CLAUDE.md"
}

@test "pal_container_rules_ensure creates empty file when missing" {
    run pal_container_rules_ensure
    assert_success
    [ -f "$HOME/.config/sandbox-pal/container-CLAUDE.md" ]
    run cat "$HOME/.config/sandbox-pal/container-CLAUDE.md"
    assert_output ""
}

@test "pal_container_rules_sync_to_container copies file into container" {
    fake_docker_set_running
    pal_container_rules_ensure
    echo "do not run destructive commands" \
        > "$HOME/.config/sandbox-pal/container-CLAUDE.md"
    run pal_container_rules_sync_to_container
    assert_success
    run grep "cp .*container-CLAUDE.md sandbox-pal-workspace:/home/agent/.claude/CLAUDE.md" "$FAKE_DOCKER_LOG"
    assert_success
}
```

- [ ] **Step 2: Run, confirm failures**

- [ ] **Step 3: Commit**

```bash
git add tests/test_container_rules.bats
git commit -m "test: container-rules file management + sync (failing)"
```

### Task 5.2: Implement `lib/container-rules.sh`

**Files:**
- Create: `lib/container-rules.sh`

- [ ] **Step 1: Write**

```bash
# lib/container-rules.sh
# shellcheck shell=bash
# Manage the host file that becomes the container's /home/agent/.claude/CLAUDE.md.

. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"

pal_container_rules_path() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '%s/sandbox-pal/container-CLAUDE.md\n' "$base"
}

pal_container_rules_ensure() {
    local path
    path="$(pal_container_rules_path)"
    if [ ! -f "$path" ]; then
        mkdir -p "$(dirname "$path")"
        : > "$path"
    fi
}

pal_container_rules_sync_to_container() {
    local path
    path="$(pal_container_rules_path)"
    [ -f "$path" ] || return 0
    docker cp "$path" "${PAL_WORKSPACE_NAME}:/home/agent/.claude/CLAUDE.md"
}

pal_container_rules_edit() {
    pal_container_rules_ensure
    local path editor
    path="$(pal_container_rules_path)"
    editor="${EDITOR:-vi}"
    "$editor" "$path"
}
```

- [ ] **Step 2: Run tests**

Expected: pass.

- [ ] **Step 3: shellcheck**

- [ ] **Step 4: Commit**

```bash
git add lib/container-rules.sh
git commit -m "feat(lib): add container-rules management (XDG-aware)"
```

---

## Phase 6: Launcher rework — docker exec

### Task 6.1: Read current launcher to confirm symbols

**Files:**
- Read only: `lib/launcher.sh`

- [ ] **Step 1: List public functions**

Run: `grep -E '^pal_' lib/launcher.sh`
Record: `pal_launch_sync`, `pal_launch_async`, `pal_cancel_run`, `pal_render_status_summary`, any others. No changes yet.

### Task 6.2: Failing test — launcher uses docker exec, syncs memory + rules first

**Files:**
- Create or modify: `tests/test_launcher.bats`

- [ ] **Step 1: Write tests**

```bash
@test "pal_launch_sync calls ensure-running, syncs, then docker exec (not docker run)" {
    fake_docker_set_running
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude/projects/-home-me-repos-foo/memory"
    echo "# idx" > "$HOME/.claude/projects/-home-me-repos-foo/memory/MEMORY.md"

    GH_TOKEN=ghp_x \
    run pal_launch_sync implement owner/repo 42 /home/me/repos/foo run-test-1
    assert_success

    run grep -- "^run -d" "$FAKE_DOCKER_LOG"
    assert_failure   # must NOT be using `docker run` anymore

    run grep -- "^exec .*sandbox-pal-workspace.*run-pipeline.sh implement owner/repo 42" "$FAKE_DOCKER_LOG"
    assert_success

    run grep -- "^cp .*container-CLAUDE.md" "$FAKE_DOCKER_LOG"
    assert_success
}

@test "pal_launch_sync forwards GH_TOKEN but NOT CLAUDE_CODE_OAUTH_TOKEN" {
    fake_docker_set_running
    export GH_TOKEN=ghp_x
    export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-should-be-ignored

    run pal_launch_sync implement owner/repo 42 /tmp/repo run-test-2
    assert_success

    run grep -- "-e GH_TOKEN" "$FAKE_DOCKER_LOG"
    assert_success
    run grep -- "CLAUDE_CODE_OAUTH_TOKEN" "$FAKE_DOCKER_LOG"
    assert_failure
}
```

- [ ] **Step 2: Run, confirm failures**

- [ ] **Step 3: Commit**

```bash
git add tests/test_launcher.bats
git commit -m "test: launcher uses docker exec and drops Claude env vars (failing)"
```

### Task 6.3: Rewrite `pal_launch_sync`

**Files:**
- Modify: `lib/launcher.sh`

- [ ] **Step 1: Replace function body**

```bash
# pal_launch_sync <event-type> <repo> <number> <host-repo-path> <run-id>
#
# Runs the pipeline inside the long-lived workspace container via docker exec.
# Requires workspace to be running and authenticated (enforced upstream by
# preflight). Memory and container-CLAUDE.md are synced before exec.
pal_launch_sync() {
    local event_type="$1"
    local repo="$2"
    local number="$3"
    local host_repo_path="$4"
    local run_id="$5"

    . "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"
    . "${CLAUDE_PLUGIN_ROOT}/lib/memory-sync.sh"
    . "${CLAUDE_PLUGIN_ROOT}/lib/container-rules.sh"

    pal_workspace_ensure_running

    local container_workdir="/home/agent/work/${run_id}"
    pal_memory_sync_to_container "$host_repo_path" "$container_workdir"
    pal_container_rules_sync_to_container

    local -a env_args=(-e "GH_TOKEN=${GH_TOKEN:?}" -e "RUN_ID=${run_id}")
    [ -n "${AGENT_TEST_COMMAND:-}" ]       && env_args+=(-e "AGENT_TEST_COMMAND=${AGENT_TEST_COMMAND}")
    [ -n "${AGENT_TEST_SETUP_COMMAND:-}" ] && env_args+=(-e "AGENT_TEST_SETUP_COMMAND=${AGENT_TEST_SETUP_COMMAND}")
    [ -n "${PAL_ALLOWLIST_EXTRA_DOMAINS:-}" ] && env_args+=(-e "PAL_ALLOWLIST_EXTRA_DOMAINS=${PAL_ALLOWLIST_EXTRA_DOMAINS}")

    docker exec "${env_args[@]}" "$PAL_WORKSPACE_NAME" \
        /opt/pal/run-pipeline.sh "$event_type" "$repo" "$number"
}
```

Update `pal_launch_async` the same way (wrap in `&` or use the existing backgrounding mechanism — keep its shape).

Update `pal_cancel_run` to call `docker exec workspace pkill -f run-pipeline.sh` or the project's existing cancel mechanism, not `docker rm -f`.

- [ ] **Step 2: Run launcher tests**

- [ ] **Step 3: Run full suite**

Run: `bats tests/`

- [ ] **Step 4: shellcheck**

- [ ] **Step 5: Commit**

```bash
git add lib/launcher.sh
git commit -m "feat(lib): launcher uses docker exec against workspace container; drops Claude env vars"
```

---

## Phase 7: New skills — pal-workspace, pal-login, pal-logout

### Task 7.1: `/pal-workspace` skill

**Files:**
- Create: `skills/pal-workspace/SKILL.md`
- Create: `commands/pal-workspace.md`

- [ ] **Step 1: Skill definition**

```markdown
---
name: pal-workspace
description: Manage the sandbox-pal workspace container (start, stop, restart, status, edit-rules).
---

# pal-workspace

Subcommands:

- `start`      — start workspace (or restart if already running)
- `stop`       — graceful stop
- `restart`    — stop + start
- `status`     — print container state + auth state
- `edit-rules` — open `$EDITOR` on `~/.config/sandbox-pal/container-CLAUDE.md`

```bash
set -euo pipefail
. "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"
. "${CLAUDE_PLUGIN_ROOT}/lib/container-rules.sh"

pal_load_config

case "${1:-status}" in
    start)
        if docker inspect "$PAL_WORKSPACE_NAME" >/dev/null 2>&1 \
            && docker ps --format '{{.Names}}' | grep -Fxq "$PAL_WORKSPACE_NAME"; then
            echo "pal: workspace already running — restarting"
            pal_workspace_restart
        else
            pal_workspace_start
        fi
        pal_workspace_status
        ;;
    stop)       pal_workspace_stop ;;
    restart)    pal_workspace_restart; pal_workspace_status ;;
    status)     pal_workspace_status ;;
    edit-rules) pal_container_rules_edit ;;
    *)          echo "usage: pal-workspace {start|stop|restart|status|edit-rules}" >&2; exit 2 ;;
esac
```
```

- [ ] **Step 2: Slash-command prompt**

```markdown
# /sandbox-pal:pal-workspace

Manage the long-running sandbox-pal workspace container.

Usage: `/pal-workspace [start|stop|restart|status|edit-rules]`

If no subcommand is given, print status.

Invoke the `pal-workspace` skill.
```

- [ ] **Step 3: BATS smoke test**

```bash
# tests/test_skill_pal_workspace.bats
@test "pal-workspace status runs end-to-end" {
    fake_docker_set_running
    run bash -c '. "$CLAUDE_PLUGIN_ROOT/skills/pal-workspace/SKILL.md.sh" status'
    # (or adapt to however other skill-smoke tests run — e.g. extracting the
    # bash block and sourcing it; mirror test_skill_pal_implement.bats.)
    assert_success
    assert_output --partial "sandbox-pal-workspace"
}
```

Match the existing test_skill_pal_implement.bats extraction pattern — don't invent a new one.

- [ ] **Step 4: Run tests, shellcheck**

- [ ] **Step 5: Commit**

```bash
git add skills/pal-workspace/ commands/pal-workspace.md tests/test_skill_pal_workspace.bats
git commit -m "feat(skills): add /pal-workspace (start/stop/restart/status/edit-rules)"
```

### Task 7.2: `/pal-login` skill

**Files:**
- Create: `skills/pal-login/SKILL.md`
- Create: `commands/pal-login.md`

- [ ] **Step 1: Skill**

```markdown
---
name: pal-login
description: Mint Claude credentials inside the workspace container via `claude /login`.
---

# pal-login

Runs the interactive `claude /login` flow inside the workspace. Auto-starts
the workspace if stopped. Requires a TTY.

```bash
set -euo pipefail
. "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"

pal_load_config
pal_workspace_ensure_running

docker exec -it "$PAL_WORKSPACE_NAME" claude /login
```
```

- [ ] **Step 2: Command prompt**

```markdown
# /sandbox-pal:pal-login

Mint Claude credentials inside the workspace container.

This opens an interactive `claude /login` flow (browser dance). Run once per
workspace lifetime; credentials persist in the Docker-managed named volume
`sandbox-pal-claude` until you run `/pal-logout` or delete the volume.

Invoke the `pal-login` skill.
```

- [ ] **Step 3: Smoke test (best-effort — interactive exec is hard to exercise)**

Skip a BATS test for `/pal-login`; document limitation in `tests/test_skill_pal_login.bats` with a single test that asserts the skill file is present and parses.

- [ ] **Step 4: Commit**

```bash
git add skills/pal-login/ commands/pal-login.md tests/test_skill_pal_login.bats
git commit -m "feat(skills): add /pal-login for in-container credential mint"
```

### Task 7.3: `/pal-logout` skill

**Files:**
- Create: `skills/pal-logout/SKILL.md`
- Create: `commands/pal-logout.md`

- [ ] **Step 1: Skill**

```markdown
---
name: pal-logout
description: Delete Claude credentials from the workspace container.
---

# pal-logout

```bash
set -euo pipefail
. "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
. "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"

pal_load_config
pal_workspace_ensure_running

docker exec "$PAL_WORKSPACE_NAME" rm -f /home/agent/.claude/.credentials.json
echo "pal: credentials removed. Run /pal-login to mint fresh ones."
```
```

- [ ] **Step 2: Command prompt**

Brief — mirror pal-login.md's style.

- [ ] **Step 3: Commit**

```bash
git add skills/pal-logout/ commands/pal-logout.md
git commit -m "feat(skills): add /pal-logout"
```

---

## Phase 8: Rewrite `/pal-setup`

### Task 8.1: New pal-setup flow

**Files:**
- Modify: `commands/pal-setup.md`

- [ ] **Step 1: Replace file content**

```markdown
# /sandbox-pal:pal-setup

Guided, one-time setup for sandbox-pal.

Walk the user through:

1. Verify `docker` is on PATH and reachable.
2. Verify `GH_TOKEN` (or `GITHUB_TOKEN`) is exported in the shell. If missing,
   instruct:
       echo 'export GH_TOKEN=github_pat_<token>' >> ~/.bashrc
       source ~/.bashrc
   The PAT needs `Contents`, `Pull requests`, `Issues` (read/write) on target repos.
3. `docker pull sandbox-pal:latest`  (or build locally from `image/`).
4. Run `/pal-workspace start` — creates the named volume and the long-running
   workspace container.
5. Run `/pal-login` — mints Claude credentials inside the workspace (one-time
   interactive browser flow). Credentials persist in the `sandbox-pal-claude`
   named volume; they never touch the host filesystem.
6. (Optional) `/pal-workspace edit-rules` — opens an empty
   `~/.config/sandbox-pal/container-CLAUDE.md` that will be synced into the
   container on every run. Use it for container-scoped behavior rules.
7. (Optional) create `~/.config/sandbox-pal/config.env` with non-secret knobs:
       PAL_CPUS=2.0
       PAL_MEMORY=4g
       PAL_SYNC_MEMORIES=true
       PAL_SYNC_TRANSCRIPTS=false

Report back what was verified and what still needs doing.
```

- [ ] **Step 2: Remove any references to `claude setup-token` or `CLAUDE_CODE_OAUTH_TOKEN` in `commands/pal-brainstorm.md`**

Run: `grep -rn "CLAUDE_CODE_OAUTH_TOKEN\|setup-token" commands/ skills/ README.md CLAUDE.md`
If matches, remove them.

- [ ] **Step 3: Commit**

```bash
git add commands/pal-setup.md commands/pal-brainstorm.md
git commit -m "feat(commands): rewrite /pal-setup for workspace-container model"
```

---

## Phase 9: Wire workspace + sync into pal-implement and pal-revise

### Task 9.1: Update `skills/pal-implement/SKILL.md`

**Files:**
- Modify: `skills/pal-implement/SKILL.md`

- [ ] **Step 1: Read current skill**

Identify the bash block. It currently sources `config.sh`, `preflight.sh`, `launcher.sh`, generates a run_id, and calls `pal_launch_*`.

- [ ] **Step 2: Edit the bash block to source workspace + memory + rules libs and pass host-repo-path**

Replacements:

- Source block at top gains:
  ```bash
  . "${CLAUDE_PLUGIN_ROOT}/lib/workspace.sh"
  . "${CLAUDE_PLUGIN_ROOT}/lib/memory-sync.sh"
  . "${CLAUDE_PLUGIN_ROOT}/lib/container-rules.sh"
  ```
- Before `pal_launch_sync`/`_async`, derive host repo path:
  ```bash
  HOST_REPO_PATH="$(git -C . rev-parse --show-toplevel)"
  ```
- Launch call signature gains the two new trailing positional args:
  ```bash
  pal_launch_sync implement "$REPO" "$NUMBER" "$HOST_REPO_PATH" "$RUN_ID"
  ```

- [ ] **Step 3: Update `tests/test_skill_pal_implement.bats`**

Add assertions for memory sync + rules sync side effects using the fake-docker shim.

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add skills/pal-implement/SKILL.md tests/test_skill_pal_implement.bats
git commit -m "feat(skill): pal-implement wires in workspace ensure + memory sync"
```

### Task 9.2: Same for `/pal-revise`

**Files:**
- Modify: `skills/pal-revise/SKILL.md`
- Modify: `tests/test_revise_smoke.bats`

- [ ] **Step 1: Mirror the edits from 9.1**

- [ ] **Step 2: Run tests**

- [ ] **Step 3: Commit**

```bash
git add skills/pal-revise/SKILL.md tests/test_revise_smoke.bats
git commit -m "feat(skill): pal-revise wires in workspace ensure + memory sync"
```

### Task 9.3: Sanity-pass on other skills

**Files:**
- Modify: `skills/pal-cancel/SKILL.md`, `skills/pal-status/SKILL.md`, `skills/pal-logs/SKILL.md`, `skills/pal-plan/SKILL.md`

- [ ] **Step 1: For each skill, confirm it does not reference the old `docker run --rm`, `CLAUDE_CODE_OAUTH_TOKEN`, or ephemeral container model**

Run: `grep -l "docker run --rm\|CLAUDE_CODE_OAUTH_TOKEN" skills/`

- [ ] **Step 2: For any matches, update to the new model**

Notably, `pal-cancel` likely needs `docker exec workspace pkill -f run-pipeline.sh` or similar. `pal-status` and `pal-logs` read `/status/<run-id>/` from the workspace; check whether their `docker` calls are compatible.

- [ ] **Step 3: Run full test suite**

Run: `shellcheck $(find . -name '*.sh' -not -path './tests/test_helper/bats-*/*') && bats tests/`

- [ ] **Step 4: Commit**

```bash
git add skills/
git commit -m "chore(skills): migrate remaining skills to workspace exec model"
```

---

## Phase 10: Documentation update phase

This phase is a REQUIREMENT of the spec (§7). Every doc listed here must be touched.

### Task 10.1: Rewrite `CLAUDE.md` (project root) authentication section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the "Authentication model" section**

```markdown
## Authentication model

sandbox-pal uses a **long-running workspace container** that owns its own Claude
credentials. `claude /login` is run interactively **inside** the container
once; the resulting `.credentials.json` persists in a Docker-managed named
volume (`sandbox-pal-claude`) and never touches the host filesystem. Every
`pal-*` invocation `docker exec`s into the workspace.

The host shell only needs `GH_TOKEN` (or `GITHUB_TOKEN`) — there is **no**
`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` env-var path. `lib/config.sh`
asserts `GH_TOKEN` and optionally sources `~/.config/sandbox-pal/config.env` for
non-secret knobs (`PAL_CPUS`, `PAL_MEMORY`, `PAL_SYNC_MEMORIES`,
`PAL_SYNC_TRANSCRIPTS`).

Per-repo non-secret knobs (`PAL_TEST_CMD`, `AGENT_BASE_BRANCH`, `DOCKER_HOST`)
may still live in `<project>/.pal/config.env`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md describes workspace-container auth model"
```

### Task 10.2: Rewrite `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite the Authentication section**

```markdown
## Authentication

sandbox-pal uses a **long-running workspace container**. Claude credentials are
minted inside the container via `claude /login` and persisted in a
Docker-managed named volume — they never touch the host filesystem.

Only `GH_TOKEN` lives in your host shell.

### One-time setup

```bash
# 1. GitHub PAT (fine-grained, Contents + Pull requests + Issues read/write)
export GH_TOKEN=github_pat_<token>   # add to ~/.bashrc or ~/.zshrc

# 2. Pull (or build) the image
docker pull sandbox-pal:latest

# 3. Start the workspace and mint Claude credentials
/pal-setup     # creates the named volume + workspace container
/pal-login     # interactive browser flow, run once per workspace lifetime
```

### Resource caps (optional)

Knobs in `~/.config/sandbox-pal/config.env`:

    PAL_CPUS=2.0
    PAL_MEMORY=4g
    PAL_SYNC_MEMORIES=true
    PAL_SYNC_TRANSCRIPTS=false

Changes apply on `/pal-workspace restart`.

### Terms of Service

Running `claude /login` inside a long-lived container under your own
subscription is endorsed by Anthropic's Legal & Compliance docs and mirrors
Anthropic's reference `.devcontainer`. Do not share the workspace volume or
expose the container to other users.
```

- [ ] **Step 2: Update the "What it does" section to note that the pipeline `docker exec`s into the workspace**

- [ ] **Step 3: Remove the "Per-repo config (non-secret)" section's env-passthrough wording if now inaccurate; keep `.pal/config.env` description**

- [ ] **Step 4: Update "Plugin skills and commands" list to include `/pal-workspace`, `/pal-login`, `/pal-logout`**

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): rewrite auth + setup for workspace-container model"
```

### Task 10.3: Rewrite `docs/install.md`

**Files:**
- Modify: `docs/install.md`

- [ ] **Step 1: Match README.md setup flow**

Replace any `setup-token` / `CLAUDE_CODE_OAUTH_TOKEN` content with the `/pal-setup` + `/pal-login` flow. Explicitly call out:
- Required Docker version.
- `GH_TOKEN` scopes.
- Where the named volume lives (`docker volume inspect sandbox-pal-claude`).
- Troubleshooting: `/pal-workspace status` first stop.

- [ ] **Step 2: Commit**

```bash
git add docs/install.md
git commit -m "docs(install): rewrite for workspace-container model"
```

### Task 10.4: New `docs/authentication.md`

**Files:**
- Create: `docs/authentication.md`

- [ ] **Step 1: Write**

Single source of truth for the new auth model. Sections:

1. TL;DR (`/pal-setup` → `/pal-login`, no env-var auth).
2. Why not env-var auth (summarize §4 of the spec; cite Claude Code Legal & Compliance).
3. How credentials live in the named volume; how to inspect it.
4. Multi-subscription / ToS notes (single-user, single-account; don't share).
5. Migration notes (if user had a `CLAUDE_CODE_OAUTH_TOKEN` set — delete it).
6. Troubleshooting.

Cross-link:
- `https://code.claude.com/docs/en/legal-and-compliance`
- `https://github.com/anthropics/claude-code/tree/main/.devcontainer`
- `docs/superpowers/specs/2026-04-21-sandbox-pal-auth-rework.md`

- [ ] **Step 2: Commit**

```bash
git add docs/authentication.md
git commit -m "docs: add authentication.md as single source of truth for auth model"
```

### Task 10.5: Update per-skill SKILL.md preamble text

**Files:**
- Modify: all `skills/pal-*/SKILL.md` frontmatter / description if they reference old behavior.

- [ ] **Step 1: Grep for stale auth language**

Run: `grep -l "setup-token\|CLAUDE_CODE_OAUTH_TOKEN\|ephemeral\|docker run --rm" skills/`

- [ ] **Step 2: Update any hits to reference the workspace model instead**

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "docs(skills): remove stale env-auth / ephemeral language"
```

### Task 10.6: Mark old plan superseded

**Files:**
- Modify: `docs/superpowers/plans/2026-04-18-sandbox-pal.md`

- [ ] **Step 1: Add a note at the top (above the H1)**

```markdown
> **SUPERSEDED** (2026-04-21): The container-lifecycle and authentication sections of this plan are superseded by `docs/superpowers/plans/2026-04-21-workspace-container-rework.md`. Pipeline-contract and review-gate tasks below remain authoritative.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-04-18-sandbox-pal.md
git commit -m "docs(plan): mark 2026-04-18 plan superseded"
```

### Task 10.7: Insert supersede markers into original spec

**Files:**
- Modify: `docs/superpowers/specs/2026-04-18-sandbox-pal-design.md`

- [ ] **Step 1: For each of §3, §5.2, §5.6, §6.1, §6.2, §9.3, insert a pointer at the top of that section**

```markdown
> **SUPERSEDED** (2026-04-21): See `docs/superpowers/specs/2026-04-21-sandbox-pal-auth-rework.md` — §N. Content below is preserved for history.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-18-sandbox-pal-design.md
git commit -m "docs(spec): insert supersede markers in original design doc"
```

### Task 10.8: CHANGELOG — minor version bump

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a new top entry**

```markdown
## [0.(X+1).0] — 2026-04-21

### Changed
- **BREAKING (pre-1.0):** Ephemeral `docker run --rm` + `CLAUDE_CODE_OAUTH_TOKEN` env-passthrough replaced by a long-running workspace container (`sandbox-pal-workspace`) with in-container `/login`. See `docs/authentication.md`.
- `lib/config.sh` no longer reads `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`. `GH_TOKEN` is the only required host env var.
- Per-run host → container memory sync (`~/.claude/projects/<slug>/memory/` → workspace). Markdown only; `*.jsonl` excluded by default (secret-tier).
- Container-scoped `CLAUDE.md` via `~/.config/sandbox-pal/container-CLAUDE.md`; synced per run.
- New optional knobs: `PAL_CPUS`, `PAL_MEMORY`, `PAL_SYNC_MEMORIES`, `PAL_SYNC_TRANSCRIPTS`.

### Added
- `/pal-workspace` (start | stop | restart | status | edit-rules).
- `/pal-login`, `/pal-logout`.
- `docs/authentication.md`.

### Removed
- `image/opt/pal/entrypoint.sh` (split into `workspace-boot.sh` + `run-pipeline.sh`).
- `claude setup-token` is no longer part of setup.
```

Determine `X+1` by reading the current CHANGELOG's most recent heading.

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): 0.(X+1).0 — workspace-container rework"
```

---

## Phase 11: Final validation and merge prep

### Task 11.1: Full lint + test pass

- [ ] **Step 1: shellcheck**

Run: `shellcheck $(find . -name '*.sh' -not -path './tests/test_helper/bats-*/*')`
Expected: zero warnings.

- [ ] **Step 2: BATS**

Run: `bats tests/`
Expected: all green.

- [ ] **Step 3: Plugin validate**

Run: `claude plugin validate .`
Expected: "Validation passed".

- [ ] **Step 4: Manual smoke in a real session**

```bash
claude --plugin-dir "$(pwd)"
# in session:
/pal-workspace status          # expect "absent"
/pal-setup                     # walkthrough
/pal-workspace start
/pal-workspace status          # expect running, auth missing
/pal-login                     # interactive
/pal-workspace status          # expect running, auth present
/pal-workspace edit-rules      # opens empty file
# exit; rm workspace; confirm clean restart works
```

- [ ] **Step 5: If anything breaks, fix and commit before merging.**

### Task 11.2: Open PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/workspace-container-rework
```

- [ ] **Step 2: Create PR**

Title: `feat: workspace-container rework — drop OAuth env, `/login` inside container, memory sync`

Body cross-links:
- `docs/superpowers/specs/2026-04-21-sandbox-pal-auth-rework.md`
- `docs/superpowers/plans/2026-04-21-workspace-container-rework.md`
- `docs/authentication.md`

### Task 11.3: Restore stashed WIP (from earlier branch switch)

- [ ] **Step 1: Check stash list**

Run: `git stash list`

- [ ] **Step 2: If the `WIP: oss-health CHANGELOG/README mods` stash is still there, note it in the PR description as a follow-up to re-apply on the `chore/oss-health-scaffolding` branch after this PR lands. Do NOT apply it to this branch.**

---

## Self-review (to perform after writing — already done)

1. **Spec coverage**: §4 base-image choice (Phase 1), §5.1 lifecycle (Phase 2), §5.2 entrypoint split (Phase 1), §5.3 named volume (Phase 1+2), §5.4 per-run wipe (run-pipeline.sh trap in Phase 1.3), §5.5 memory sync (Phase 4), §5.6 container CLAUDE.md (Phase 5), §5.7 env passthrough (Phase 6), §5.8 resource caps (Phase 2/3), §5.9 auto-start (Phase 2.4), §6 Windows roadmap (explicit no-op), §7 doc updates (Phase 10). All covered.
2. **Placeholders**: none — every code step has complete code or explicit "mirror existing pattern X" with the referenced file named.
3. **Type consistency**: `$PAL_WORKSPACE_NAME`, `$PAL_WORKSPACE_VOLUME`, `$PAL_WORKSPACE_IMAGE` consistent across lib files. `pal_memory_slug`, `pal_memory_sync_to_container`, `pal_container_rules_*` names stable between tests and impls. `pal_launch_sync` signature `(event-type, repo, number, host-repo-path, run-id)` used consistently from tests and skills.
