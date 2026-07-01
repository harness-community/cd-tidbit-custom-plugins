"""Kanboard plugin step entrypoint.

Reads config from env vars (injected by Harness as Plugin step settings) and
moves a single Kanboard task into the column corresponding to the current
environment.

Harness Plugin steps inject `settings:` keys into the container with a
`PLUGIN_` prefix (Drone plugin convention), so `settings.KANBOARD_URL`
arrives as `PLUGIN_KANBOARD_URL`.

Env vars expected:
    PLUGIN_KANBOARD_URL           e.g. http://kanboard.kanboard.svc.cluster.local:8080/jsonrpc.php
    PLUGIN_KANBOARD_API_TOKEN     API token from Kanboard → My Profile → API
    PLUGIN_KANBOARD_PROJECT_ID    integer
    PLUGIN_KANBOARD_TASK_ID       integer (the demo task to move)
    PLUGIN_KANBOARD_COL           integer column id for THIS environment

Filled in during build phase; this stub captures the shape so docs/parity refs
have something to point at.
"""

import os
import sys

import kanboard  # pip install kanboard


def main() -> int:
    url = os.environ["PLUGIN_KANBOARD_URL"]
    token = os.environ["PLUGIN_KANBOARD_API_TOKEN"]
    project_id = int(os.environ["PLUGIN_KANBOARD_PROJECT_ID"])
    task_id = int(os.environ["PLUGIN_KANBOARD_TASK_ID"])
    column_id = int(os.environ["PLUGIN_KANBOARD_COL"])

    with kanboard.Client(url, "jsonrpc", token) as kb:
        kb.move_task_position(
            project_id=project_id,
            task_id=task_id,
            column_id=column_id,
            position=1,
            swimlane_id=1,
        )
    print(f"moved task {task_id} to column {column_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
