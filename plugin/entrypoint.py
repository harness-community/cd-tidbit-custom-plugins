"""Kanboard plugin step entrypoint.

Reads config from env vars (injected by Harness as Plugin step settings) and
moves a single Kanboard task into the column corresponding to the current
environment.

Env vars expected:
    KANBOARD_URL           e.g. http://kanboard.kanboard.svc.cluster.local:8080/jsonrpc.php
    KANBOARD_API_TOKEN     API token from Kanboard → My Profile → API
    KANBOARD_PROJECT_ID    integer
    KANBOARD_TASK_ID       integer (the demo task to move)
    KANBOARD_COL           integer column id for THIS environment

Filled in during build phase; this stub captures the shape so docs/parity refs
have something to point at.
"""

import os
import sys

import kanboard  # pip install kanboard


def main() -> int:
    url = os.environ["KANBOARD_URL"]
    token = os.environ["KANBOARD_API_TOKEN"]
    project_id = int(os.environ["KANBOARD_PROJECT_ID"])
    task_id = int(os.environ["KANBOARD_TASK_ID"])
    column_id = int(os.environ["KANBOARD_COL"])

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
