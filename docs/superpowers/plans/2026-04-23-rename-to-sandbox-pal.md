# Rename claude-pal → sandbox-pal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Perform a brand-only rename of the literal `claude-pal` to `sandbox-pal` across the repository. The `pal-*` command/skill namespace, `PAL_*` env vars, `.pal/` per-repo dir, and version `0.5.0` are untouched. Two tokens are preserved intact: `claude-pal-action` (sibling repo) and `claude-pal-token` (GitHub PAT filename).

**Architecture:** Mechanical substitution, grouped by logical unit with a commit per group. Each group updates production code and its BATS tests together so the suite stays green commit-to-commit. A two-pass sed pattern (`claude-pal → sandbox-pal`, then restore `sandbox-pal-action → claude-pal-action` and `sandbox-pal-token → claude-pal-token`) handles bulk text in docs; targeted edits handle semantically-sensitive identifiers (manifest fields, env-var defaults).

**Tech Stack:** Bash, BATS-Core, Docker, sed, grep, git.

**Spec:** [`docs/superpowers/specs/2026-04-23-rename-to-sandbox-pal-design.md`](../specs/2026-04-23-rename-to-sandbox-pal-design.md)

**Branch:** `rename-to-sandbox-pal` (already created off `main`; spec already committed).

**Preserved exceptions (must NOT be renamed):**
- `jnurre64/claude-pal-action` — sibling repo reference (appears in `README.md`, `CHANGELOG.md`, `docs/authentication.md`, `docs/superpowers/specs/2026-04-19-oss-health-skill-design.md`, `docs/superpowers/plans/2026-04-18-claude-pal.md`)
- `claude-pal-token` — GitHub PAT filename (appears in `docs/superpowers/plans/2026-04-23-plugin-marketplace.md`)
- Pre-rename `CHANGELOG.md` entries under the `[0.5.0]` and earlier headings that describe historical behavior at the time of release — specifically when the text refers to artifacts that no longer exist under the old name (keep as historical truth; new Unreleased entry documents the rename)
- Historical commit messages and existing git tags `v0.4.0`, `v0.5.0`
- The spec doc `docs/superpowers/specs/2026-04-23-rename-to-sandbox-pal-design.md` (it intentionally names both the old and new brand)

---

### Task 1: Baseline verification + exception enumeration

**Files:** none modified.

**Purpose:** Confirm the suite is green before the rename starts, and lock in the exact expected exception list so Task 12's grep-sanity step has something concrete to compare against.

- [ ] **Step 1: Confirm branch and clean tree**

Run:
```bash
git branch --show-current
git status
```
Expected: branch `rename-to-sandbox-pal`, clean working tree (spec already committed).

- [ ] **Step 2: Run shellcheck**

Run:
```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0, no output.

- [ ] **Step 3: Run the full BATS suite**

Run:
```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 4: Snapshot the baseline claude-pal reference count and exception list**

Run:
```bash
grep -rln "claude-pal" --exclude-dir=.git . | wc -l
grep -rln "claude-pal-action\|claude-pal-token" --exclude-dir=.git .
```
Expected: a count (~50 files); second command lists only the pre-identified exception-bearing files (`README.md`, `CHANGELOG.md`, `docs/authentication.md`, `docs/superpowers/plans/2026-04-18-claude-pal.md`, `docs/superpowers/plans/2026-04-23-plugin-marketplace.md`, `docs/superpowers/specs/2026-04-19-oss-health-skill-design.md`, `docs/superpowers/specs/2026-04-23-rename-to-sandbox-pal-design.md`).

- [ ] **Step 5: No commit (verification only)**

---

### Task 2: Rename Docker identifiers (image tag, volume names, container name)

**Files:**
- Modify: `lib/image.sh` (line 5)
- Modify: `lib/workspace.sh` (lines 5-7)
- Modify: `lib/runs.sh` (lines 10, 15, 50)
- Modify: `scripts/build-image.sh` (lines 2, 8 — image-build helper that defaults `TAG` to `claude-pal:latest`)
- Modify: `tests/test_helper/fake-docker.sh`
- Modify: `tests/test_image.bats`
- Modify: `tests/test_image_smoke.bats`
- Modify: `tests/test_workspace_lifecycle.bats`
- Modify: `tests/test_fake_docker_shim.bats`
- Modify: `tests/test_launcher.bats`
- Modify: `tests/test_skill_pal_implement.bats`
- Modify: `tests/test_skill_pal_workspace.bats`
- Modify: `tests/test_memory_sync.bats`
- Modify: `tests/test_async_and_cancel.bats`
- Modify: `tests/test_revise_smoke.bats`
- Modify: `tests/test_container_pipeline.bats`

**Identifiers changing:**
- Image: `claude-pal:latest` → `sandbox-pal:latest`, `claude-pal:dev` → `sandbox-pal:dev`
- Volume: `claude-pal-claude` → `sandbox-pal-claude`, `claude-pal-workspace` → `sandbox-pal-workspace`
- Container name (default): `claude-pal-workspace` → `sandbox-pal-workspace`

- [ ] **Step 1: Update `lib/image.sh` line 5**

Before:
```bash
: "${PAL_WORKSPACE_IMAGE:=claude-pal:latest}"
```
After:
```bash
: "${PAL_WORKSPACE_IMAGE:=sandbox-pal:latest}"
```

Also update the file-level comment on line 3:
Before: `# Host-side helpers for the claude-pal container image.`
After: `# Host-side helpers for the sandbox-pal container image.`

- [ ] **Step 2: Update `lib/workspace.sh` lines 3, 5-7**

Before:
```bash
# Host-side lifecycle for the long-running claude-pal workspace container.
...
: "${PAL_WORKSPACE_NAME:=claude-pal-workspace}"
: "${PAL_WORKSPACE_VOLUME:=claude-pal-claude}"
: "${PAL_WORKSPACE_IMAGE:=claude-pal:latest}"
```
After:
```bash
# Host-side lifecycle for the long-running sandbox-pal workspace container.
...
: "${PAL_WORKSPACE_NAME:=sandbox-pal-workspace}"
: "${PAL_WORKSPACE_VOLUME:=sandbox-pal-claude}"
: "${PAL_WORKSPACE_IMAGE:=sandbox-pal:latest}"
```

- [ ] **Step 2b: Update `scripts/build-image.sh`**

Before (line 2, line 8):
```bash
# Build the claude-pal base image.
...
TAG="${1:-claude-pal:latest}"
```
After:
```bash
# Build the sandbox-pal base image.
...
TAG="${1:-sandbox-pal:latest}"
```

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' scripts/build-image.sh
grep -n 'claude-pal' scripts/build-image.sh || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Update `lib/runs.sh` (three sites)**

Line 10 (macOS/Linux runs dir):
Before: `echo "${XDG_DATA_HOME:-$HOME/.local/share}/claude-pal/runs"`
After:  `echo "${XDG_DATA_HOME:-$HOME/.local/share}/sandbox-pal/runs"`

Line 15 (Windows runs dir):
Before: `echo "$local_app/claude-pal/runs"`
After:  `echo "$local_app/sandbox-pal/runs"`

Line 50 (JSON snapshot default):
Before: `"image_tag": "${PAL_IMAGE_TAG:-claude-pal:latest}"`
After:  `"image_tag": "${PAL_IMAGE_TAG:-sandbox-pal:latest}"`

- [ ] **Step 4: Update `tests/test_helper/fake-docker.sh`**

Bulk substitute `claude-pal` → `sandbox-pal` in this file:
```bash
sed -i 's/claude-pal/sandbox-pal/g' tests/test_helper/fake-docker.sh
```

Verify no `claude-pal` remains:
```bash
grep -n 'claude-pal' tests/test_helper/fake-docker.sh || echo "clean"
```
Expected: `clean`.

- [ ] **Step 5: Bulk-substitute Docker identifiers in BATS files**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' \
  tests/test_image.bats \
  tests/test_image_smoke.bats \
  tests/test_workspace_lifecycle.bats \
  tests/test_fake_docker_shim.bats \
  tests/test_launcher.bats \
  tests/test_skill_pal_implement.bats \
  tests/test_skill_pal_workspace.bats \
  tests/test_memory_sync.bats \
  tests/test_async_and_cancel.bats \
  tests/test_revise_smoke.bats \
  tests/test_container_pipeline.bats
```

Verify:
```bash
grep -l 'claude-pal' tests/*.bats tests/test_helper/*.sh || echo "clean"
```
Expected: `clean`.

Note — sed uses single quotes per project convention (double quotes would expand `$PAL_*` references inside scripts).

- [ ] **Step 6: Run shellcheck**

Run:
```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0.

- [ ] **Step 7: Run BATS**

Run:
```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass (the test assertions now match the new identifiers the production code emits).

- [ ] **Step 8: Commit**

```bash
git add lib/image.sh lib/workspace.sh lib/runs.sh scripts/build-image.sh tests/
git commit -m "$(cat <<'EOF'
refactor: rename Docker image/volume/container identifiers to sandbox-pal

Image tag claude-pal:{latest,dev} → sandbox-pal:{latest,dev}. Named
volumes claude-pal-{claude,workspace} → sandbox-pal-{claude,workspace}.
Container-name default follows the volume rename.

BATS tests and the fake-docker shim updated in the same commit so the
suite stays green.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rename host config path

**Files:**
- Modify: `lib/config.sh` (lines 3, 7, 10, 19)
- Modify: `lib/container-rules.sh` (line 12)
- Modify: `tests/test_config.bats`
- Modify: `tests/test_container_rules.bats`

**Identifier changing:** `~/.config/claude-pal/` → `~/.config/sandbox-pal/` (the XDG config base).

- [ ] **Step 1: Update `lib/config.sh`**

Replace the four claude-pal references. The substitutions:
- Line 3 comment: `# claude-pal host-side config loader.` → `# sandbox-pal host-side config loader.`
- Line 7 comment: `...in the named volume \`claude-pal-claude\`...` → `...in the named volume \`sandbox-pal-claude\`...`
- Line 10 comment: `...~/.config/claude-pal/config.env:` → `...~/.config/sandbox-pal/config.env:`
- Line 19 path: `"${XDG_CONFIG_HOME:-$HOME/.config}/claude-pal/config.env"` → `"${XDG_CONFIG_HOME:-$HOME/.config}/sandbox-pal/config.env"`

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' lib/config.sh
grep -n 'claude-pal' lib/config.sh || echo "clean"
```
Expected: `clean`.

- [ ] **Step 2: Update `lib/container-rules.sh` line 12**

Before: `printf '%s/claude-pal/container-CLAUDE.md\n' "$base"`
After:  `printf '%s/sandbox-pal/container-CLAUDE.md\n' "$base"`

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' lib/container-rules.sh
grep -n 'claude-pal' lib/container-rules.sh || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Update `tests/test_config.bats` and `tests/test_container_rules.bats`**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' tests/test_config.bats tests/test_container_rules.bats
grep -n 'claude-pal' tests/test_config.bats tests/test_container_rules.bats || echo "clean"
```
Expected: `clean`.

- [ ] **Step 4: Run shellcheck**

```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0.

- [ ] **Step 5: Run BATS**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/config.sh lib/container-rules.sh tests/test_config.bats tests/test_container_rules.bats
git commit -m "$(cat <<'EOF'
refactor: rename host config path ~/.config/claude-pal → ~/.config/sandbox-pal

Config loader and container-rules helper updated; tests updated in the
same commit.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Rename prose in remaining host-side lib files

**Files:**
- Modify: `lib/launcher.sh` (lines 3, 141, 144, 148, 239, 243, 247, 252, 257, 260)
- Modify: `lib/notify.sh` (line 6)
- Modify: `lib/publisher.sh` (line 19)

**Purpose:** user-visible strings printed by `launcher.sh` (e.g., `printf '✓ claude-pal run %s: success\n'`), notification titles (`local title="${1:-claude-pal}"`), and GitHub issue titles (`title="claude-pal implementation plan ($(date -I))"`).

- [ ] **Step 1: Bulk-substitute the three files**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' lib/launcher.sh lib/notify.sh lib/publisher.sh
grep -n 'claude-pal' lib/launcher.sh lib/notify.sh lib/publisher.sh || echo "clean"
```
Expected: `clean`.

- [ ] **Step 2: Check whether any BATS test asserts against these strings**

Run:
```bash
grep -rn "claude-pal run\|claude-pal implementation\|\${1:-claude-pal}\|title.*claude-pal" tests/ 2>/dev/null || echo "no test assertions"
```
Expected: `no test assertions` (checked during planning; these strings are not asserted by the existing suite — if the grep surfaces a match, update the matching test the same way).

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0.

- [ ] **Step 4: Run BATS**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/launcher.sh lib/notify.sh lib/publisher.sh
git commit -m "$(cat <<'EOF'
refactor: rename claude-pal → sandbox-pal in launcher/notify/publisher prose

User-visible strings in terminal output, notification titles, and
GitHub issue titles now say sandbox-pal.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Rename in-container scripts and prompts

**Files:**
- Modify: `image/opt/pal/run-pipeline.sh` (lines 108, 288, 291)
- Modify: `image/opt/pal/lib/worktree.sh` (lines 43-44)
- Modify: `image/opt/pal/lib/review-gates.sh` (lines 129, 136, 140, 188, 211, 262, 290)
- Modify: `image/opt/pal/prompts/implement.md` (line 1)

- [ ] **Step 1: Bulk-substitute the container-side files**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' \
  image/opt/pal/run-pipeline.sh \
  image/opt/pal/lib/worktree.sh \
  image/opt/pal/lib/review-gates.sh \
  image/opt/pal/prompts/implement.md
```

Verify:
```bash
grep -rn 'claude-pal' image/ || echo "clean"
```
Expected: `clean`.

- [ ] **Step 2: Note the git-user default change in `image/opt/pal/lib/worktree.sh`**

After substitution, lines 43-44 read:
```bash
local bot_name="${AGENT_GIT_USER_NAME:-sandbox-pal}"
local bot_email="${AGENT_GIT_USER_EMAIL:-sandbox-pal@local}"
```

These are the default git author identity for commits made inside the container when `AGENT_GIT_USER_*` aren't set. No test covers these defaults directly. No further action.

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0.

- [ ] **Step 4: Run BATS**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass (the `test_container_pipeline.bats` test already had its Docker-identifier refs updated in Task 2).

- [ ] **Step 5: Commit**

```bash
git add image/
git commit -m "$(cat <<'EOF'
refactor: rename claude-pal → sandbox-pal in container-side scripts

run-pipeline.sh log prefix, PR title fallback, and PR body; worktree.sh
git-user defaults; review-gates.sh comments and error-comment bodies;
implement.md prompt.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Rename plugin manifests + move marketplace ref to main

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Changes:**
- `plugin.json`: `name`, `repository`
- `marketplace.json`: top-level `name`, `metadata.description`, `plugins[0].name`, `plugins[0].source.repo`, `plugins[0].source.ref` (`"v0.5.0"` → `"main"`), `plugins[0].homepage`, `plugins[0].description`

- [ ] **Step 1: Rewrite `.claude-plugin/plugin.json`**

Full new file contents:
```json
{
  "name": "sandbox-pal",
  "version": "0.5.0",
  "description": "Local agent dispatch for Claude Code — publishes implementation plans to GitHub and runs a gated pipeline (adversarial plan review → TDD implement → post-impl review → PR) inside a long-running Docker workspace container.",
  "author": { "name": "jnurre64" },
  "repository": "https://github.com/jnurre64/sandbox-pal",
  "license": "MIT",
  "keywords": ["agents", "automation", "github", "docker"]
}
```
Note — `version` stays at `0.5.0` per spec. `description` wording is unchanged (the word "claude-pal" does not appear inside it).

- [ ] **Step 2: Rewrite `.claude-plugin/marketplace.json`**

Full new file contents:
```json
{
  "name": "sandbox-pal",
  "owner": { "name": "jnurre64" },
  "metadata": {
    "description": "Self-hosted marketplace for sandbox-pal — a Claude Code plugin that dispatches agent runs against GitHub issues inside a long-running Docker workspace container."
  },
  "plugins": [
    {
      "name": "sandbox-pal",
      "source": {
        "source": "github",
        "repo": "jnurre64/sandbox-pal",
        "ref": "main"
      },
      "description": "Local agent dispatch for Claude Code — publishes implementation plans to GitHub and runs a gated pipeline (adversarial plan review → TDD implement → post-impl review → PR) inside a long-running Docker workspace container.",
      "homepage": "https://github.com/jnurre64/sandbox-pal",
      "category": "automation"
    }
  ]
}
```
Note — `source.ref: "main"` (moved from `"v0.5.0"` per spec). All other fields ported straight over with `claude-pal` → `sandbox-pal`.

- [ ] **Step 3: Verify both manifests parse**

Run:
```bash
jq -e . .claude-plugin/plugin.json > /dev/null && echo "plugin.json OK"
jq -e . .claude-plugin/marketplace.json > /dev/null && echo "marketplace.json OK"
```
Expected: `plugin.json OK` then `marketplace.json OK`.

- [ ] **Step 4: Validate plugin manifest with Claude Code**

Run:
```bash
claude plugin validate ~/repos/claude-pal
```
Expected: `✔ Validation passed`.

- [ ] **Step 5: Run BATS (confirms nothing else broke)**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "$(cat <<'EOF'
refactor: rename plugin manifests to sandbox-pal; pin marketplace to main

plugin.json: name + repository URL.
marketplace.json: top-level name, metadata.description, nested plugin
name/source.repo/homepage/description, and source.ref moved from v0.5.0
to main — the v0.5.0 tag's plugin.json still says claude-pal and cannot
be retroactively renamed without force-moving the tag.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Rename skills and commands

**Files:**
- Modify: `skills/pal-implement/SKILL.md`
- Modify: `skills/pal-plan/SKILL.md`
- Modify: `skills/pal-workspace/SKILL.md`
- Modify: `skills/pal-cancel/SKILL.md`
- Modify: `skills/pal-status/SKILL.md`
- Modify: `skills/pal-logs/SKILL.md`
- Modify: `skills/pal-revise/SKILL.md`
- Modify: `skills/pal-login/SKILL.md` (if it has claude-pal refs — check)
- Modify: `skills/pal-logout/SKILL.md` (if it has claude-pal refs — check)
- Modify: `commands/pal-setup.md`
- Modify: `commands/pal-workspace.md`
- Modify: `commands/pal-login.md`
- Modify: `commands/pal-logout.md`
- Modify: `commands/pal-brainstorm.md`

**What changes:** prose mentions of `claude-pal` (workspace, container, volume `claude-pal-claude`, config path `~/.config/claude-pal/`, image `claude-pal:latest`), plus slash-command invocation prefix `/claude-pal:pal-*` → `/sandbox-pal:pal-*` (the part before the colon is the plugin name, which is changing).

The skill/command directory names (`pal-*`) and the command names themselves (`pal-setup`, etc.) **do not change**.

- [ ] **Step 1: Bulk substitute in all skill and command files**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' skills/pal-*/SKILL.md commands/pal-*.md
```

Note — this handles both `/claude-pal:pal-foo` references (which become `/sandbox-pal:pal-foo`) and prose mentions. The `pal-foo` suffix after the colon is untouched because the sed pattern looks for `claude-pal`, not `pal-foo`.

- [ ] **Step 2: Verify no claude-pal remains**

Run:
```bash
grep -rn 'claude-pal' skills/ commands/ || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Restore sibling-repo reference if any was damaged**

Check whether any of the edited files referenced `claude-pal-action`:
```bash
grep -rn 'sandbox-pal-action' skills/ commands/ || echo "no sibling refs"
```
Expected: `no sibling refs` (sibling repo is only referenced in README and a few docs, not in skills/commands). If any match appears, restore with:
```bash
sed -i 's/sandbox-pal-action/claude-pal-action/g' <matched files>
```

- [ ] **Step 4: Run BATS**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 5: Validate the plugin still loads**

Run:
```bash
claude plugin validate ~/repos/claude-pal
```
Expected: `✔ Validation passed`.

- [ ] **Step 6: Commit**

```bash
git add skills/ commands/
git commit -m "$(cat <<'EOF'
refactor: rename claude-pal → sandbox-pal in skill and command docs

SKILL.md descriptions, command prose, volume references, config paths,
image tags, and /claude-pal:pal-* invocation examples now say
sandbox-pal. Command and skill names (pal-*) unchanged.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Rename top-level and installation docs

**Files:**
- Modify: `README.md` (preserve two `claude-pal-action` refs on lines 42, 44)
- Modify: `CLAUDE.md`
- Modify: `CONTRIBUTING.md`
- Modify: `SECURITY.md`
- Modify: `UPSTREAM.md`
- Modify: `docs/install.md`
- Modify: `docs/authentication.md` (preserve two `claude-pal-action` refs on lines 25, 52)

`CODE_OF_CONDUCT.md` has zero `claude-pal` refs (verified in planning); skip.

- [ ] **Step 1: Two-pass substitute with exception restore**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' \
  README.md CLAUDE.md CONTRIBUTING.md SECURITY.md UPSTREAM.md \
  docs/install.md docs/authentication.md

sed -i 's/sandbox-pal-action/claude-pal-action/g; s/sandbox-pal-token/claude-pal-token/g' \
  README.md CLAUDE.md CONTRIBUTING.md SECURITY.md UPSTREAM.md \
  docs/install.md docs/authentication.md
```

- [ ] **Step 2: Verify the exception restore worked**

Run:
```bash
grep -n 'claude-pal-action' README.md docs/authentication.md
```
Expected: `README.md:42:...Relationship to \`claude-pal-action\``, `README.md:44:...\`claude-pal-action\`...`, `docs/authentication.md:25:...\`claude-pal-action\`...`, `docs/authentication.md:52:...\`claude-pal-action\`...` (i.e., the four original sibling refs survive).

```bash
grep -n '\bclaude-pal\b' README.md CLAUDE.md CONTRIBUTING.md SECURITY.md UPSTREAM.md docs/install.md docs/authentication.md || echo "only claude-pal-action remains"
```
Expected: only lines containing `claude-pal-action` (not bare `claude-pal`).

- [ ] **Step 3: Spot-check README.md**

Read README.md and confirm:
- Title / intro now says "sandbox-pal"
- Getting started block uses `/plugin marketplace add jnurre64/sandbox-pal` and `/plugin install sandbox-pal@sandbox-pal`
- Docker image references say `sandbox-pal:latest`
- The "Relationship to `claude-pal-action`" section header and its two surrounding references to the sibling repo are intact

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md CONTRIBUTING.md SECURITY.md UPSTREAM.md docs/install.md docs/authentication.md
git commit -m "$(cat <<'EOF'
docs: rename claude-pal → sandbox-pal in top-level and install docs

Preserves sibling-repo references to jnurre64/claude-pal-action in
README and docs/authentication.md (those are a separate project).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Add CHANGELOG Unreleased section + rename going-forward references

**Files:**
- Modify: `CHANGELOG.md` (preserve line 43 `jnurre64/claude-pal-action` sibling ref)

**Purpose:** introduce an `## [Unreleased]` section above `## [0.5.0]` documenting the rename + migration steps. Update all going-forward `claude-pal` references in existing entries **except** historical descriptions that must remain truthful about artifacts at their release time, and except the sibling repo reference on line 43.

**Policy:** treat previously-dated entries the same as other docs — rename the brand throughout, except for (a) line 43's sibling repo reference, and (b) any entry whose meaning requires the old name (re-read after substitution; if any line becomes false or nonsensical, revert that specific line).

**Step order matters**: rename existing `[0.5.0]` entries **first**, then insert the Unreleased block. If reversed, the sed pass would rewrite the literal `claude-pal` identifiers inside the Unreleased migration commands (which are deliberately present to describe the old-state-to-new-state copy).

- [ ] **Step 1: Snapshot the sibling reference line**

Run:
```bash
grep -n 'claude-pal-action' CHANGELOG.md
```
Expected: one line under the `[0.5.0]` `### Added` block referencing `jnurre64/claude-pal-action`. Note its line number — you'll confirm it survives the sed pass.

- [ ] **Step 2: Two-pass substitute existing CHANGELOG entries**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' CHANGELOG.md
sed -i 's/sandbox-pal-action/claude-pal-action/g' CHANGELOG.md
```

Verify the sibling ref is intact and no bare claude-pal remains in the existing entries:
```bash
grep -n 'claude-pal-action' CHANGELOG.md
grep -n '\bclaude-pal\b' CHANGELOG.md | grep -v 'claude-pal-action' || echo "no bare claude-pal"
```
Expected: one `claude-pal-action` line; `no bare claude-pal`.

- [ ] **Step 3: Re-read `## [0.5.0]` entries for meaning-breaking changes**

The `[0.5.0]` section mentions a BREAKING change and names `claude-pal-workspace` (now `sandbox-pal-workspace` after sed). That's acceptable going-forward branding — readers coming from the old installation will understand from the Unreleased section's migration note. If you find any entry whose substituted form misrepresents historical state (e.g., "used to be called X"), leave the original wording intact. As of planning, no such entry exists.

- [ ] **Step 4: Insert the Unreleased section above `## [0.5.0]`**

Open `CHANGELOG.md`. Between the top-level `# Changelog` line and the `## [0.5.0] — 2026-04-23` heading, insert the block shown below. The literal `claude-pal` references inside this block are intentional — they document the old identifiers the user is migrating from. Do **not** sed over this file again after this insertion.

The block to insert (copy verbatim — note the inner triple-backtick fence for the migration shell snippet):

````````markdown
## [Unreleased]

### Changed
- **Brand rename:** `claude-pal` → `sandbox-pal`. The plugin, Docker image (`sandbox-pal:latest`), named volumes (`sandbox-pal-claude`, `sandbox-pal-workspace`), host config path (`~/.config/sandbox-pal/`), and marketplace identifiers are all renamed. The `pal-*` command/skill names, `PAL_*` env vars, and per-repo `.pal/` config directory are unchanged. Version stays at 0.5.0.
- `marketplace.json` now pins `source.ref: "main"` rather than a tag — the `v0.5.0` tag's committed `plugin.json` still says `claude-pal`, so tracking `main` keeps the installed plugin consistent with its manifest until the next release.

### Migration (for existing claude-pal users)

The rename orphans three pieces of local state. None are auto-migrated; each has a one-line fix:

```bash
# 1. Credentials volume — the new workspace uses sandbox-pal-claude; start fresh by re-running
#    claude /login inside the new workspace, OR copy the old volume contents:
docker run --rm \
  -v claude-pal-claude:/src \
  -v sandbox-pal-claude:/dst \
  alpine sh -c 'cp -a /src/. /dst/'

# 2. Workspace scratch volume (if you care about its contents):
docker run --rm \
  -v claude-pal-workspace:/src \
  -v sandbox-pal-workspace:/dst \
  alpine sh -c 'cp -a /src/. /dst/'

# 3. Host config:
cp -r ~/.config/claude-pal ~/.config/sandbox-pal
```

The old `claude-pal:latest` Docker image is orphaned; `/pal-setup` will rebuild as `sandbox-pal:latest` on next run. You can remove the old image with `docker image rm claude-pal:latest` once the new one is working.

The `/plugin` marketplace entry (if you installed via `/plugin marketplace add jnurre64/claude-pal`) needs to be re-added: run `/plugin marketplace remove claude-pal`, then `/plugin marketplace add jnurre64/sandbox-pal` and `/plugin install sandbox-pal@sandbox-pal`.
````````

- [ ] **Step 5: Verify the final state**

Run:
```bash
grep -n '^## ' CHANGELOG.md | head -3
```
Expected: `## [Unreleased]` on an early line, then `## [0.5.0] — 2026-04-23`, then `## [0.4.0]` (or whatever the next heading is).

```bash
grep -n 'claude-pal' CHANGELOG.md
```
Expected: the `claude-pal-action` sibling line, plus all the intentional `claude-pal` mentions inside the Unreleased Migration block (volume names in `docker run`, config path in `cp`, image tag in `docker image rm`, marketplace commands).

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): add Unreleased rename entry + migration; update prior entries

New Unreleased section documents the claude-pal → sandbox-pal rename
and the three manual migration steps for users with existing state.
Previously-dated entries renamed going-forward (sibling repo reference
preserved).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Rename docs/superpowers/ design & plan filenames and content

**Files (renamed via `git mv`):**
- `docs/superpowers/specs/2026-04-18-claude-pal-design.md` → `docs/superpowers/specs/2026-04-18-sandbox-pal-design.md`
- `docs/superpowers/plans/2026-04-18-claude-pal.md` → `docs/superpowers/plans/2026-04-18-sandbox-pal.md`
- `docs/superpowers/plans/2026-04-21-claude-pal-auth-rework.md` → `docs/superpowers/plans/2026-04-21-sandbox-pal-auth-rework.md`

**Content preservation rules:**
- In `docs/superpowers/plans/2026-04-18-sandbox-pal.md`, preserve line 3800-3838 area where `claude-pal-action` appears (sibling repo ref).
- The spec doc `docs/superpowers/specs/2026-04-23-rename-to-sandbox-pal-design.md` intentionally mentions the old brand — **do not edit** (skip in sed).
- `docs/superpowers/specs/2026-04-19-oss-health-skill-design.md` mentions both `claude-pal-action` and `claude-pal` (line 12) — preserve the sibling ref, rename the product ref.
- `docs/superpowers/plans/2026-04-23-plugin-marketplace.md` mentions `claude-pal-token` on lines 892, 1013, 1052, 1097 — preserve the PAT filename. Other `claude-pal` mentions in that file rename going-forward.

- [ ] **Step 1: `git mv` the three renamed files**

Run:
```bash
git mv docs/superpowers/specs/2026-04-18-claude-pal-design.md \
       docs/superpowers/specs/2026-04-18-sandbox-pal-design.md

git mv docs/superpowers/plans/2026-04-18-claude-pal.md \
       docs/superpowers/plans/2026-04-18-sandbox-pal.md

git mv docs/superpowers/plans/2026-04-21-claude-pal-auth-rework.md \
       docs/superpowers/plans/2026-04-21-sandbox-pal-auth-rework.md
```

Verify:
```bash
git status --short
```
Expected: three `R  old -> new` lines (git detects renames).

- [ ] **Step 2: Two-pass substitute content inside all `docs/superpowers/` files EXCEPT this plan and the rename spec**

Run:
```bash
find docs/superpowers -name '*.md' \
  -not -name '2026-04-23-rename-to-sandbox-pal-design.md' \
  -not -name '2026-04-23-rename-to-sandbox-pal.md' \
  -exec sed -i 's/claude-pal/sandbox-pal/g' {} +

find docs/superpowers -name '*.md' \
  -not -name '2026-04-23-rename-to-sandbox-pal-design.md' \
  -not -name '2026-04-23-rename-to-sandbox-pal.md' \
  -exec sed -i 's/sandbox-pal-action/claude-pal-action/g; s/sandbox-pal-token/claude-pal-token/g' {} +
```

- [ ] **Step 3: Verify exceptions survived**

Run:
```bash
grep -rn 'claude-pal-action' docs/superpowers/
grep -rn 'claude-pal-token' docs/superpowers/
grep -rn '\bclaude-pal\b' docs/superpowers/ \
  | grep -v '2026-04-23-rename-to-sandbox-pal-design.md' \
  | grep -v '2026-04-23-rename-to-sandbox-pal.md' \
  || echo "only rename-spec/plan mention the old brand"
```
Expected: the first two commands print each sibling/token ref from the planning snapshot; the third prints `only rename-spec/plan mention the old brand`.

- [ ] **Step 4: Spot-check a renamed file opens coherently**

Read the first 30 lines of `docs/superpowers/specs/2026-04-18-sandbox-pal-design.md` and confirm the title, goal, and early prose read naturally under the new name. (Since this was a design doc for the original project, you may encounter phrasings like "sandbox-pal ships as a Claude Code plugin" — that's fine.)

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/
git commit -m "$(cat <<'EOF'
docs(superpowers): rename claude-pal → sandbox-pal in specs and plans

Three files renamed via git mv to preserve history:
- specs/2026-04-18-claude-pal-design.md → sandbox-pal-design.md
- plans/2026-04-18-claude-pal.md → sandbox-pal.md
- plans/2026-04-21-claude-pal-auth-rework.md → sandbox-pal-auth-rework.md

Content renamed throughout docs/superpowers/ except the rename spec
and this plan (which intentionally name both brands). Sibling repo
(claude-pal-action) and PAT filename (claude-pal-token) references
preserved.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Rename .github/ issue templates and `.pal/` example config

**Files:**
- Modify: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Modify: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Modify: `.pal/config.env.example` (lines 1, 4 — comments mention the `claude-pal` brand; the `.pal/` directory name itself is NOT renamed per spec non-goal)

- [ ] **Step 1: Substitute**

Run:
```bash
sed -i 's/claude-pal/sandbox-pal/g' \
  .github/ISSUE_TEMPLATE/bug_report.yml \
  .github/ISSUE_TEMPLATE/feature_request.yml \
  .pal/config.env.example
```

- [ ] **Step 2: Verify no claude-pal remains**

```bash
grep -n 'claude-pal' .github/ISSUE_TEMPLATE/*.yml .pal/config.env.example || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Verify the YAML still parses**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/bug_report.yml'))" && echo "bug_report OK"
python3 -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/feature_request.yml'))" && echo "feature_request OK"
```
Expected: `bug_report OK` and `feature_request OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE/ .pal/config.env.example
git commit -m "$(cat <<'EOF'
docs: rename claude-pal → sandbox-pal in issue templates and per-repo example

.pal/ directory name itself is unchanged (non-goal per spec); only the
brand references inside the example file text.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Final verification (no new commits)

**Purpose:** prove the rename is complete and nothing regressed. The grep-sanity step is the single most important check — it enumerates the surviving `claude-pal` occurrences and confirms they match the exception list from Task 1.

- [ ] **Step 1: Run shellcheck on every shell file**

```bash
shellcheck $(find . -name '*.sh' -not -path '*/bats/*' -not -path '*/.git/*')
```
Expected: exit 0, no output.

- [ ] **Step 2: Run the full BATS suite**

```bash
./tests/bats/bin/bats tests/
```
Expected: all tests pass.

- [ ] **Step 3: Grep sanity — surviving `claude-pal` references**

Run:
```bash
grep -rln 'claude-pal' --exclude-dir=.git .
```
Expected: matches ONLY these files, with the reasons documented:

| File | Reason |
|---|---|
| `docs/superpowers/specs/2026-04-23-rename-to-sandbox-pal-design.md` | rename spec intentionally names both brands |
| `docs/superpowers/plans/2026-04-23-rename-to-sandbox-pal.md` | this plan, same reason |
| `README.md` | two `claude-pal-action` sibling-repo refs (lines ~42, ~44 pre-rename) |
| `CHANGELOG.md` | one `claude-pal-action` sibling-repo ref (under historical `[0.5.0]` entry); plus `claude-pal` mentions inside the Unreleased migration block (intentional — describes the rename) |
| `docs/authentication.md` | two `claude-pal-action` sibling-repo refs |
| `docs/superpowers/plans/2026-04-18-sandbox-pal.md` | one `claude-pal-action` sibling-repo ref |
| `docs/superpowers/specs/2026-04-19-oss-health-skill-design.md` | two `claude-pal-action` sibling-repo refs |
| `docs/superpowers/plans/2026-04-23-plugin-marketplace.md` | four `claude-pal-token` PAT-filename refs |

If any other file appears, investigate — it is either a missed substitution or a newly-discovered exception that needs documenting.

Run a targeted check that specifically isolates the bare `claude-pal` brand (no `-action` / `-token` suffix, no inside-migration-block mentions):
```bash
grep -rn '\bclaude-pal\b' --exclude-dir=.git . \
  | grep -v 'claude-pal-action' \
  | grep -v 'claude-pal-token' \
  | grep -v '2026-04-23-rename-to-sandbox-pal'
```
Expected: matches only inside the CHANGELOG Unreleased Migration block (where `claude-pal-claude` / `claude-pal-workspace` / `claude-pal:latest` appear as the *source* names in the `docker run` copy commands and `docker image rm`).

- [ ] **Step 4: Validate the plugin manifest**

```bash
claude plugin validate ~/repos/claude-pal
```
Expected: `✔ Validation passed`.

- [ ] **Step 5: Runtime smoke test**

Open a session:
```bash
claude --plugin-dir ~/repos/claude-pal
```

Inside the session:
- `/skills` — verify the `pal-*` skills still list correctly (directory names and skill names unchanged).
- Invoke `/sandbox-pal:pal-workspace status` — confirm the plugin prefix is now `sandbox-pal` (the command will report the container as stopped or missing, which is expected — we don't build the new image as part of this verification).

Exit the session.

- [ ] **Step 6: Git log review**

```bash
git log --oneline main..HEAD
```
Expected: one spec commit, one motivation-update commit, and ten task commits — roughly twelve commits on the branch, each with a clear refactor/docs prefix.

- [ ] **Step 7: No new commit (verification only)**

---

## After the plan: follow-ups outside this PR

Once this PR merges to `main`, the user performs these steps manually (documented in the spec, repeated here for convenience):

1. **Rename the GitHub repo:** Settings → Rename `jnurre64/claude-pal` → `jnurre64/sandbox-pal`.
2. **Update local remote:** `git remote set-url origin https://github.com/jnurre64/sandbox-pal.git`.
3. **Optional:** rename the local working directory `~/repos/claude-pal` → `~/repos/sandbox-pal`.

These steps are out of scope for the rename PR itself.
