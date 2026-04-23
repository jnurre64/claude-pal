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
