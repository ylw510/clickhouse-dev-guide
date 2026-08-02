#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${ROOT}/env.sh"
CLIENT="${CLICKHOUSE_CLIENT}"
HOST="${CH_HOST}"

usage()
{
  cat <<EOF
Usage: $(basename "$0") [node] [clickhouse-client args...]

Quick connect to a cluster_2s2r ClickHouse node.

Nodes:
  1  node1  s1r1  shard1-replica1   native 19100  http 18223
  2  node2  s1r2  shard1-replica2   native 19101  http 18224
  3  node3  s2r1  shard2-replica1   native 19102  http 18225
  4  node4  s2r2  shard2-replica2   native 19103  http 18226

Examples:
  $(basename "$0")                 # connect to node1
  $(basename "$0") 2               # connect to node2
  $(basename "$0") node3 -q "SELECT version()"
  $(basename "$0") 4 -q "SELECT * FROM system.clusters WHERE cluster='demo_2s2r'"

Environment (see env.sh):
  CLICKHOUSE_BIN_DIR   path to programs dir
  CH_HOST              client host (default: 127.0.0.1)
EOF
}

resolve_node()
{
  case "${1,,}" in
    1|node1|n1|s1r1) echo 1 ;;
    2|node2|n2|s1r2) echo 2 ;;
    3|node3|n3|s2r1) echo 3 ;;
    4|node4|n4|s2r2) echo 4 ;;
    -h|--help|help) usage; exit 0 ;;
    *)
      echo "Unknown node: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

node_port()
{
  case "$1" in
    1) echo 19100 ;;
    2) echo 19101 ;;
    3) echo 19102 ;;
    4) echo 19103 ;;
    *) echo "invalid node: $1" >&2; exit 1 ;;
  esac
}

NODE=1
if [[ $# -gt 0 && "${1}" != -* ]]; then
  if [[ "${1}" =~ ^[1-4]$ || "${1,,}" =~ ^(node[1-4]|n[1-4]|s[12]r[12])$ ]]; then
    NODE="$(resolve_node "$1")"
    shift
  fi
fi

PORT="$(node_port "${NODE}")"

exec "${CLIENT}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --connect_timeout 30 \
  "$@"
