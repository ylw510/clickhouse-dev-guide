#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for pidfile in "${ROOT}"/node{1,2,3,4}/server.pid "${ROOT}"/keeper{1,2,3}/keeper.pid; do
  if [[ -f "${pidfile}" ]]; then
    pid="$(<"${pidfile}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      echo "Stopping PID ${pid} (${pidfile})..."
      kill "${pid}" 2>/dev/null || true
    fi
  fi
done

sleep 2
pkill -f "clickhouse-server.*${ROOT}/node" 2>/dev/null || true
pkill -f "clickhouse-keeper.*${ROOT}/keeper" 2>/dev/null || true
rm -f "${ROOT}"/keeper{1,2,3}/keeper.pid "${ROOT}"/node{1,2,3,4}/server.pid
echo "Stopped (best effort)."
