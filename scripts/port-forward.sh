#!/usr/bin/env bash
#
# port-forward.sh — Foreground port-forward to the demo app (Dev/QA/Prod)
# AND to Kanboard.
#
# Auto-reconnects when the underlying pod rotates (every deploy / rollback).
# Ctrl-C stops all forwards cleanly. Output from each forward is prefixed
# with [dev]/[qa]/[prod]/[kanboard] so the streams are distinguishable.
#
set -uo pipefail

# Suppress bash's job-control "Terminated:" notices when we kill descendants.
set +m

# Recursively collect all descendant PIDs of $1 (deepest first).
descendants() {
  local pid=$1
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    descendants "$child"
  done
  echo "$pid"
}

cleanup() {
  trap - INT TERM EXIT
  local pids
  pids=$(for c in $(pgrep -P $$ 2>/dev/null); do descendants "$c"; done)
  { [ -n "$pids" ] && kill -KILL $pids 2>/dev/null || true; wait; } 2>/dev/null
  echo
  echo "port-forward stopped."
  exit 0
}
trap cleanup INT TERM EXIT

forward() {
  local label="$1" port="$2" svc="$3" svc_port="$4" ns="$5"
  while true; do
    kubectl port-forward "svc/${svc}" "${port}:${svc_port}" -n "$ns" 2>&1 \
      | sed "s/^/[$label] /"
    echo "[$label] connection lost — reconnecting in 2s…"
    sleep 2
  done
}

forward dev      8080 custom-plugins-demo 80   web-dev  &
forward qa       8081 custom-plugins-demo 80   web-qa   &
forward prod     8082 custom-plugins-demo 80   web-prod &
forward kanboard 8090 kanboard            8080 kanboard &

sleep 1
echo
echo "Dev:      http://127.0.0.1:8080"
echo "QA:       http://127.0.0.1:8081"
echo "Prod:     http://127.0.0.1:8082"
echo "Kanboard: http://127.0.0.1:8090   (default admin/admin)"
echo "Ctrl-C to stop."
echo

wait
