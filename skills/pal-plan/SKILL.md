---
name: pal-plan
description: Publish an implementation plan from the current conversation to a GitHub issue. Takes the most recent plan file in docs/superpowers/plans/ (or an explicit --file path) and posts it as a comment with <!-- agent-plan --> marker. Creates a new issue if no issue number given. Does NOT launch a container — provides a checkpoint to review the posted plan on GitHub before running /pal-implement.
---

# pal-plan

Publish a plan to GitHub for later dispatch.

## Usage

```
/pal-plan [issue#] [--file <path>]
```

## Steps

1. Parse arguments: zero or one positional issue number; optional `--file <path>`.
2. Source shared libs (Claude Code sets `${CLAUDE_PLUGIN_ROOT}` when the skill fires):
   ```bash
   . "${CLAUDE_PLUGIN_ROOT}/lib/config.sh"
   . "${CLAUDE_PLUGIN_ROOT}/lib/plan-locator.sh"
   . "${CLAUDE_PLUGIN_ROOT}/lib/publisher.sh"
   ```
3. Load config: `pal_load_config`.
4. Locate the plan file: `plan_file=$(pal_find_plan_file "$file_arg")`. On failure, exit with the locator's error.
5. Determine target repo from cwd's git origin, or require `PAL_REPO` env var.
6. Publish: `pal_publish_plan "$plan_file" "$repo" "$issue_arg"`.
7. The publisher prints the issue URL and a "Next step: /pal-implement <issue#>" hint.

## Examples

- `/pal-plan` — auto-detect latest plan, create a new issue with it
- `/pal-plan 42` — auto-detect latest plan, post as comment on issue #42
- `/pal-plan 42 --file docs/superpowers/plans/2026-04-18-feature.md` — post a specific plan on issue #42
