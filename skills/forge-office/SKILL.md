---
name: forge-office
description: >
  This skill should be used to open, stop, or configure the bundled forge-office
  dashboard — phrases like "forge-office", "open the dashboard", "show the office",
  "start the kanban board", "stop the dashboard", or "start the dashboard
  automatically". It launches the plugin's local, read-only web dashboard (kanban
  from the progress tracker, live agent office, activity feed) for the current
  project, and can enable autostart so it runs with every session.
metadata:
  version: "0.33.1"
---

# forge-office

The plugin bundles a local web dashboard (`dashboard/` in the plugin root): a
kanban board parsed from `progress-tracker.md` + the build plan, live claims and
locks, an activity feed from the local metrics, and a 2D pixel office where the
nine forge agents visibly work (desks, meeting table, lounge).

Read-only by design — the dashboard never writes to the project. It binds to
127.0.0.1 only. Requires Node ≥ 18.

## Argument

- *(none)* or `start` → start for the current project and print the URL.
- `stop` → stop the server.
- `status` → running state, project, URL, autostart setting.
- `autostart on` / `autostart off` → start automatically at `SessionStart` in
  any Context Forge project (silent, one URL line when it starts fresh).

## Steps

1. Run the launcher with the requested action:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/forge-office/scripts/forge-office.sh" <action>
   ```

   `start` is idempotent (an already-running server is reported, not duplicated)
   and verifies the server actually serves before reporting success. On macOS it
   opens the browser; otherwise relay the URL.
2. Relay the script's output verbatim — it contains the URL and, on failure,
   the log path (`~/.claude/forge-office/<port>.log`).
3. If the user asked for automatic behavior ("always run this"), use
   `autostart on` and mention it applies to every Context Forge project on this
   machine.

## Notes

- Port: `$FORGE_OFFICE_PORT` (default 4820). One server per port; a second
  project needs a different port.
- The live agent presence and the activity feed come from the plugin's own
  hooks (agent-status, metrics — on by default since 0.29.0); no setup needed.
- Never expose the port publicly; for remote access recommend a private
  tailnet (Tailscale).
