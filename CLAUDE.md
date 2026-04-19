# claude-pal

Local agent dispatch via Claude Code skills.

## Key Documentation

- Full design: `docs/superpowers/specs/2026-04-18-claude-pal-design.md`
- Implementation plan: `docs/superpowers/plans/2026-04-18-claude-pal.md`
- Upstream tracking (vendored pieces): `UPSTREAM.md`

## Architecture

- `image/Dockerfile` — base Ubuntu image with claude CLI, gh, jq, git, iptables
- `image/opt/pal/entrypoint.sh` — pipeline orchestrator (bash)
- `image/opt/pal/allowlist.yaml` — firewall allowlist (data)
- `image/opt/pal/prompts/` — vendored adversarial/post-impl review prompts
- `image/opt/pal/lib/` — bash helpers (vendored review-gates.sh etc.)
- `skills/pal-*/SKILL.md` — Claude Code skills (host-side)
- `skills/lib/` — shared skill helpers (config loader, notifier, etc.)
- `tests/` — BATS-Core tests

## Development

- All shell scripts must pass `shellcheck` with zero warnings
- Tests use BATS-Core
- Run checks: `shellcheck $(find . -name '*.sh') && bats tests/`
- Use `set -euo pipefail` in all scripts
