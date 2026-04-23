---
title: sandbox-pal — Auth and Container-Lifecycle Rework
status: draft
date: 2026-04-21
author: jonny (with Claude)
supersedes_sections_of: 2026-04-18-sandbox-pal-design.md  # §3, §5.2, §5.6, §6.1, §9.3
---

# sandbox-pal — Auth and Container-Lifecycle Rework

## 1. Why this doc exists

The original design (`2026-04-18-sandbox-pal-design.md`) locked in an **ephemeral `docker run --rm` + `CLAUDE_CODE_OAUTH_TOKEN` env-passthrough** model. Research into prior art revealed a better path: a long-running workspace container with `claude /login` run *inside* the container, modeled on Anthropic's own reference `.devcontainer`.

This doc evaluates the candidate models, picks one, and sketches the diff against the current spec. Pipeline contract, review gates, status schema, and skill surface all stay.

## 2. Terminology cleanup — what "Docker sbx" isn't

The question that prompted this rework used "Docker sbx." Research clarified:

- **Claude Code sandboxing is OS-native, not Docker.** macOS uses Seatbelt, Linux/WSL2 uses bubblewrap. There is no official `docker/sandbox-templates:claude-code` image — the existing spec's §6.1 and §9.3 reference is aspirational.
- **Sandboxing is per-CLI-invocation.** No reattach. Can't replace a container model.
- **Sandboxing *can* run inside Docker** via `enableWeakerNestedSandbox`, but it's explicitly "weaker" and intended only where outer isolation already exists.
- **`@anthropic-ai/sandbox-runtime`** (npm, open source) wraps arbitrary commands in the same bubblewrap/Seatbelt primitives — optional defense-in-depth inside our container, not a backend.

Takeaway: sbx is orthogonal defense-in-depth, not a backend choice.

## 3. Options evaluated

### Option A — Status quo (ephemeral + `CLAUDE_CODE_OAUTH_TOKEN` env-passthrough)

`claude setup-token` once on host → token in shell env → forwarded to `docker run --rm` → container runs one pipeline and exits.

Endorsed but at the margins. Extra setup step, silent-override footgun (`ANTHROPIC_API_KEY`), token rotation chore.

### Option B — Long-running workspace container, `/login` inside (chosen)

A single named container starts once; `claude /login` runs interactively once inside; `.credentials.json` persists in a Docker-managed named volume. Every `pal-*` invocation `docker exec`s into the container and runs `claude` there. Container stays up across sessions (start-on-demand after reboot).

**Chosen.** See §4 for rationale and §5 for implementation shape.

### Option C — Hybrid: persistent auth container + ephemeral worker containers

A small long-lived container owns `.credentials.json`; ephemeral workers read it at launch.

**Rejected.** This is literally "credential forwarding" by the docs' wording — the mount pattern Anthropic explicitly prohibits. No ToS win over B.

### Option D — Claude Managed Agents (official service)

Pay per session-hour + tokens; use Console API key.

**Rejected.** Wrong niche for sandbox-pal. Not local, not personal-subscription-backed. Noted for completeness.

## 4. Why Option B — base image choice and rationale

### Base off Anthropic's `.devcontainer`, cherry-pick data patterns from Claudebox

Anthropic's reference `.devcontainer` (`github.com/anthropics/claude-code/tree/main/.devcontainer`) is the closest fit:

- **Vendor-official.** Tacit ToS endorsement for the `/login`-inside-container pattern.
- **Minimal** (~92-line Dockerfile + firewall script) vs Claudebox's ~400-line entrypoint with profiles/slots/tmux — all DX-wrapper concerns sandbox-pal doesn't need.
- **Named Docker volume** for `/home/node/.claude` — no host-side secrets file at all. Cleaner permissions story than bind-mounts.
- **Strong default-deny firewall**: `NET_ADMIN`+`NET_RAW` caps, `iptables -P OUTPUT DROP`, `ipset` for allowed domains, fetches GitHub CIDRs at startup, includes a verification step that tries reaching a non-allowlisted host to confirm the deny works.
- **Single-user, single-account** by design — matches our topology.

**Cherry-pick from Claudebox.** Keep the sandbox-pal `allowlist.yaml` data-file pattern. Borrow the "re-resolve on container start" flow (Claudebox's `getent` pass over a text file) rather than baking IPs at build time.

### ToS posture of Option B

Direct quotes from official sources:

> "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications."
> — code.claude.com/docs/en/legal-and-compliance

Since sandbox-pal runs the native CLI under a single human's subscription, this is endorsed. `/login` inside the container is exactly what Anthropic's reference `.devcontainer` does.

> "A single developer, on their own machine, keeping one long-running container with `/login` done inside it, `docker exec`-ing in for repeated personal CLI use, is indistinguishable under the documented rules from keeping a terminal tab open on the laptop for weeks."
> — research synthesis, 2026-04-21

> "Advertised usage limits for Pro and Max plans assume ordinary, individual usage…"
> — code.claude.com/docs/en/legal-and-compliance

Volume pressure ("ordinary individual usage") is the only residual concern, and it's orthogonal to container lifetime.

### OAuth token path dropped entirely

`CLAUDE_CODE_OAUTH_TOKEN` is not a fallback. Setup is `/pal-setup` + `/pal-login` — there is no env-var auth path. Rationale:

- One auth path = one set of failure modes to document and debug.
- Removes the `ANTHROPIC_API_KEY` silent-override footgun (no Claude env vars in the host shell at all).
- `claude setup-token` step eliminated from user setup.

If a user insists on env-var auth, they use `claude-agent-dispatch` (sibling project) instead.

## 5. Implementation shape

### 5.1 Container lifecycle

```
Host                                    Container: sandbox-pal-workspace (long-lived)
────                                    ──────────────────────────────────────────
/pal-setup                              → docker volume create sandbox-pal-claude
                                        → docker run -d --name sandbox-pal-workspace
                                           --cap-add NET_ADMIN --cap-add NET_RAW
                                           -v sandbox-pal-claude:/home/agent/.claude
                                           [--cpus=… --memory=… if configured]
                                           sandbox-pal:latest /opt/pal/workspace-boot.sh
                                        → workspace-boot.sh: program firewall, then sleep infinity

/pal-login                              → (auto-start workspace if stopped)
                                        → docker exec -it workspace claude /login
                                          (interactive browser dance happens once)

/pal-implement 42                       → (auto-start workspace if stopped, silent + log line)
                                        → sync memory + container-CLAUDE.md into workspace
                                        → docker exec workspace /opt/pal/run-pipeline.sh
                                           implement owner/repo 42
                                        → pipeline runs, writes /status/<run-id>/ via bind mount
                                        → docker exec rm -rf per-run transient state

/pal-workspace status                   → docker ps / inspect; shows auth state, uptime, caps
/pal-workspace start                    → explicit start (restart if already running)
/pal-workspace stop                     → graceful stop
/pal-workspace restart                  → stop + start (used after config changes)
/pal-workspace edit-rules               → opens $EDITOR on ~/.config/sandbox-pal/container-CLAUDE.md

/pal-logout                             → docker exec workspace rm -f
                                          /home/agent/.claude/.credentials.json
```

### 5.2 Entrypoint split

The current `entrypoint.sh` does firewall + pipeline as one script. This splits into two:

- **`workspace-boot.sh`** — one-time-per-container-lifetime. Programs iptables/ipset from `allowlist.yaml` with re-resolution of domain → IP; runs the Anthropic-style verification (try reaching example.com, assert fails); then `sleep infinity`.
- **`run-pipeline.sh`** — invoked via `docker exec` per run. Does the clone-and-execute pipeline. No firewall changes (unless `PAL_ALLOWLIST_EXTRA_DOMAINS` differs from last run, in which case it reloads the allowlist).

### 5.3 Auth state (persistent in named volume)

Named Docker volume `sandbox-pal-claude` mounted at `/home/agent/.claude/`. Contents that persist across runs:

- `.credentials.json` — minted by `/pal-login` inside the container, never leaves.
- `.claude/settings.json` — Claude Code settings (initialized empty; user can customize via `/pal-workspace edit-settings` if we add it).
- `.claude/projects/<slug>/memory/` — written by the container's `claude` during a run. Wiped between runs (see §5.5).
- Installed MCP servers, if any (phase-2 concern).

### 5.4 Per-run transient state (wiped at end of run)

- `/home/agent/work/<run-id>/` — fresh clone per issue/PR.
- `/home/agent/.claude/projects/<container-slug>/` — session state written during the run, including any `*.jsonl` transcripts and any `memory/*.md` files the container's `claude` generated.
- Any transient `/tmp/` work.

Wipe happens unconditionally at run end, regardless of outcome.

### 5.5 Host → container memory sync (read-only, per-run)

On every `/pal-implement` or `/pal-revise`, before `docker exec`:

1. Compute host slug from the repo's host path (e.g., `/home/jonny/repos/sandbox-pal` → `-home-jonny-repos-sandbox-pal`).
2. Compute container slug from the container's planned work-dir (`/home/agent/work/<run-id>/` → `-home-agent-work-<run-id>`).
3. Wipe the container's `projects/<container-slug>/memory/` (via `docker exec rm -rf`).
4. `docker cp` host's `~/.claude/projects/<host-slug>/memory/` → container's `/home/agent/.claude/projects/<container-slug>/memory/`. **Preserve subdir structure** — native Claude Code Auto Memory (v2.1.59+) auto-loads `MEMORY.md` from the `memory/` subdir.
5. Copy includes `MEMORY.md` and all sibling `.md` topic files. **Exclude `*.jsonl`** (session transcripts — secret-tier, may contain plaintext output of `env`, `cat .env`, `gh auth token`; see research-cited 2026-03 leak incident).
6. Sync is **one-way, read-only**. Container's in-run writes to memory dir are discarded at run end (§5.4).

Scope: **current repo only.** Other projects' memories aren't relevant to the pipeline and are noise.

Config knobs in `~/.config/sandbox-pal/config.env`:

- `PAL_SYNC_MEMORIES=true` (default: true) — turn off to skip sync entirely.
- `PAL_SYNC_TRANSCRIPTS=false` (default: false) — opt-in only; includes `*.jsonl` in the sync if true. **Not recommended**; included for parity/debugging.

### 5.6 Container-level CLAUDE.md (configurable rules inside the container)

The user's host `~/.claude/CLAUDE.md` is **not** copied into the container — host-specific rules (about local filesystem, personal workflow, etc.) don't apply to the container's sandbox.

Instead, pal manages a **container-scoped** CLAUDE.md:

- Host path: `$XDG_CONFIG_HOME/sandbox-pal/container-CLAUDE.md` (fallback `~/.config/sandbox-pal/container-CLAUDE.md`).
- Default: empty file created on `/pal-setup`.
- Synced into the container at `/home/agent/.claude/CLAUDE.md` via `docker cp` on every run (same mechanism as memory sync).
- User edits via any mechanism:
  - `$EDITOR ~/.config/sandbox-pal/container-CLAUDE.md` directly.
  - Optional convenience: `/pal-workspace edit-rules` opens it in `$EDITOR`.
  - Version-controlled in their dotfiles if they want.

This is opt-in customization — if the file is empty, the container has no CLAUDE.md. Simple and predictable.

### 5.7 Per-run inputs (env vars passed on `docker exec`)

- `GH_TOKEN` — still env-passthrough (not Claude auth).
- `EVENT_TYPE`, `REPO`, `NUMBER`.
- `AGENT_TEST_COMMAND`, `AGENT_TEST_SETUP_COMMAND`.
- `AGENT_ALLOWED_TOOLS_*`, `AGENT_MODEL_*`.
- `PAL_ALLOWLIST_EXTRA_DOMAINS` — if different from last run, triggers firewall reload at run start.

### 5.8 Resource limits (uncapped default)

Optional in `~/.config/sandbox-pal/config.env`:

- `PAL_CPUS=` (default unset = uncapped; e.g., `2.0` for two-core cap).
- `PAL_MEMORY=` (default unset = uncapped; e.g., `4g` for 4 GiB cap).

Passed to `docker run` when the workspace container is first started. Changing them requires `/pal-workspace restart`.

### 5.9 Auto-start behavior

- Silent auto-start with a log line: "workspace stopped — starting…" then proceed.
- Manual `/pal-workspace start` when workspace is already running = restart (stop + start).
- Docker `--restart` policy: **not used** (start-on-demand only). Avoids always-running overhead; user has explicit control.
- `/pal-login` auto-starts the workspace if stopped.

## 6. Windows-container flexibility (v2 roadmap)

Option B is backend-agnostic. On Windows, the workspace pattern works identically:

- `docker run -d` a Windows-container base image (e.g., `mcr.microsoft.com/windows/servercore:ltsc2022` or a .NET SDK image), run `workspace-boot.ps1` instead of `workspace-boot.sh`.
- Named volume at `C:\Users\agent\.claude\`.
- `docker exec` into PowerShell instead of bash.
- Firewall: `New-NetFirewallRule` reading the same `allowlist.yaml`.
- Memory sync: `docker cp` works identically on Windows containers.

The entrypoint split (§5.2) is what makes this cheap: `workspace-boot.{sh,ps1}` and `run-pipeline.{sh,ps1}` are two sibling pairs, one per host-kernel target. Everything else (status schema, skill surface, config) is shared.

No new Windows-specific complexity vs the current v1 design. Kept explicitly on the roadmap; not a priority for this rework.

## 7. What gets rewritten in the original spec when Option B lands

The implementation plan must include a **documentation-update phase** covering all sandbox-pal docs. Specifics:

| Existing spec section | Revision |
|---|---|
| §3 ToS/threat model | Rewrite — lead with "minted-inside-container" pattern. Remove env-passthrough framing. Update citations to include the quoted Claude Code Legal & Compliance lines and the Anthropic reference devcontainer. |
| §5.2 config file schema | Remove `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`. Add `PAL_SYNC_MEMORIES`, `PAL_SYNC_TRANSCRIPTS`, `PAL_CPUS`, `PAL_MEMORY`. Document `~/.config/sandbox-pal/container-CLAUDE.md` as a managed host file. |
| §5.6 preflight | Replace "token presence check" with "workspace container healthy + authenticated" check (`docker exec workspace test -f /home/agent/.claude/.credentials.json`). Add "workspace started" auto-start behavior. |
| §6.1 base image | Drop aspirational `BASE_IMAGE` build-arg. Base on an Anthropic-devcontainer-aligned Ubuntu image (same as current, but consciously mirror its layout/user). |
| §6.2 entrypoint contract | Split into workspace-boot + run-pipeline as described in §5.2. Update the "Inputs" env-var table. Update the "Outputs" — still `/status/<run-id>/`, unchanged. |
| §9.3 future sbx backend | Rewrite. sbx is orthogonal defense-in-depth, not a backend. Note optional `@anthropic-ai/sandbox-runtime` wrap of the in-container `claude` invocation as a future polish (with `enableWeakerNestedSandbox` since we're already containerized). |

Other docs to update in the implementation plan:
- `CLAUDE.md` (project root) — auth model paragraph; `${CLAUDE_PLUGIN_ROOT}` usage (unchanged, just context); remove references to `setup-token`.
- `UPSTREAM.md` — no change (vendored review prompts are unchanged).
- `README.md` — setup flow section (`/pal-setup` + `/pal-login`); remove any mentions of `CLAUDE_CODE_OAUTH_TOKEN`.
- Per-skill `SKILL.md` files — preflight wording, setup expectations.
- New: `docs/authentication.md` (or `docs/auth-model.md`) — single source of truth for the new model; cross-links to the Claude Code Legal & Compliance page and Anthropic's `.devcontainer`.
- `CHANGELOG.md` — minor-version bump entry summarizing the rework.
- Existing plan `docs/superpowers/plans/2026-04-18-sandbox-pal.md` — mark superseded phases; new plan supersedes implementation details but references this one for pipeline-contract context.

## 8. Open implementation-detail items (resolved in implementation, not spec)

- Exact slug-encoding function (`/` → `-` per research; verify edge cases for Windows paths when v2 lands).
- Exact mechanism for `docker cp` vs `tar | docker exec cat` for memory sync (both work; pick on perf grounds).
- Container health-check interval and how `/pal-status` infers auth-state.
- Whether `/pal-workspace restart` prompts the user before killing an in-flight run.
- Exact verification-domain choice for firewall assertion (Anthropic uses `example.com`; confirm).

## 9. Out of scope for this rework

- Windows-container backend implementation (§6) — still on roadmap, architectural hooks preserved, not prioritized.
- Remote Docker via `DOCKER_HOST` — unchanged. Transport-agnostic.
- GitHub PR webhook integration, multi-user mode, scheduled loops, round-trip memory sync — still out of scope.

## 10. Versioning and migration

Minor-version bump (`0.X` → `0.(X+1)`). No users in production to migrate. Implement in place on a new branch off `main`.

---

## Appendix A: Why Anthropic's `.devcontainer` over Claudebox

| Dimension | Anthropic devcontainer | Claudebox | Chosen |
|---|---|---|---|
| Auth | `/login` inside; named Docker volume | `/login` inside; host bind mount | devcontainer (no host secrets file) |
| Vendor posture | Official, ToS-tacit-endorsed | Third-party, silent on ToS | devcontainer |
| Shape fit for headless pipeline | Low adaptation cost (~92 lines) | High adaptation cost (~400 lines, DX wrapper) | devcontainer |
| Firewall strength | iptables + ipset + CIDR fetch + verification | iptables + text-file allowlist, no verify | devcontainer (verification step) |
| Allowlist data pattern | IP bake at build time | Text file re-resolved at start | Claudebox |
| Slot / multi-auth | None (1:1 container:user) | Full slot chain | devcontainer (we're single-account) |
| Bus factor | Anthropic monorepo | Single maintainer | devcontainer |

## Appendix B: Memory-system clarification

Quoted from `code.claude.com/docs/en/memory`:

> "Each project gets its own memory directory at `~/.claude/projects/<project>/memory/`."

Native Claude Code Auto Memory (v2.1.59+) auto-loads the first 200 lines (or 25KB) of `MEMORY.md` from that subdir at SessionStart. Topic files (`.md` sibling files referenced from `MEMORY.md`) are loaded on-demand via Claude's file tools, not at startup.

**For sandbox-pal's sync: preserve the subdir structure.** Native auto-load works without any hook or CLAUDE.md mediation. Topic-file relative links stay intact.

## Appendix C: Transcript safety

Quoted from research:

> "The 2026-03 source-map leak confirmed the community's working assumption: `.claude/projects/<slug>/*.jsonl` stores every Read/Bash/Grep/Edit tool call and result in plaintext, including any secret echoed by a command (`env`, `cat .env`, `gh auth token`). Claude Code's internal `secretSanner.ts` scans prompts with ~40 regexes but does not redact transcripts after the fact."

Therefore: `*.jsonl` files are **excluded from memory sync** by default. `PAL_SYNC_TRANSCRIPTS=true` exists as an opt-in for debugging but is not recommended.

## Appendix D: Claudebox reference summary (prior art)

- `github.com/RchGrav/claudebox` (MIT, ~1k stars, solo-maintainer)
- Model: one Docker image per project, multiple "slots" per project, all interactive-first
- Auth: `/login` inside, `.credentials.json` via host bind mount at `~/.claudebox/projects/<slug>_<crc32>/<slot-crc>/`
- No `CLAUDE_CODE_OAUTH_TOKEN` support
- Does not address ToS
- Useful as: text-file allowlist pattern and "DX wrapper" counter-example
- Not useful as: base image, because of the shape mismatch (interactive-human wrapper vs headless pipeline)
