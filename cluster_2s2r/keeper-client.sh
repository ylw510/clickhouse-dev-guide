#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH="${CLICKHOUSE_BIN_DIR:-/root/work/ClickHouse/build_release/programs}"
CLIENT="${CH}/clickhouse-keeper-client"
HOST="${KEEPER_CLIENT_HOST:-${CLUSTER_IP:-192.168.153.128}}"

usage()
{
  cat <<EOF
Usage: $(basename "$0") [keeper] [clickhouse-keeper-client args...]

Quick connect to a cluster_2s2r Keeper node.

Keepers:
  1  keeper1  zk 9281  raft 9334
  2  keeper2  zk 9282  raft 9335
  3  keeper3  zk 9283  raft 9336

Examples:
  $(basename "$0")                              # connect to keeper1
  $(basename "$0") 2                            # connect to keeper2
  $(basename "$0") keeper3 -q "ls '/'"
  $(basename "$0") 1 -q "ls '/clickhouse/clusters_metadata'"
  $(basename "$0") 1 -q "get '/clickhouse/clusters_metadata'"

Environment:
  CLICKHOUSE_BIN_DIR   path to programs dir (default: /root/ClickHouse/build_release/programs)
  CLUSTER_IP           keeper bind IP from start.sh (default: 192.168.153.128)
  KEEPER_CLIENT_HOST   client host override (default: CLUSTER_IP)
EOF
}

resolve_keeper()
{
  case "${1,,}" in
    1|keeper1|k1) echo 1 ;;
    2|keeper2|k2) echo 2 ;;
    3|keeper3|k3) echo 3 ;;
    -h|--help|help) usage; exit 0 ;;
    *)
      echo "Unknown keeper: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

keeper_port()
{
  case "$1" in
    1) echo 9281 ;;
    2) echo 9282 ;;
    3) echo 9283 ;;
    *) echo "invalid keeper: $1" >&2; exit 1 ;;
  esac
}

KEEPER=1
if [[ $# -gt 0 && "${1}" != -* ]]; then
  if [[ "${1}" =~ ^[1-3]$ || "${1,,}" =~ ^(keeper[1-3]|k[1-3])$ ]]; then
    KEEPER="$(resolve_keeper "$1")"
    shift
  fi
fi

PORT="$(keeper_port "${KEEPER}")"

exec "${CLIENT}" \
  -h "${HOST}" \
  -p "${PORT}" \
  --connection-timeout 30 \
  --session-timeout 30 \
  --operation-timeout 30 \
  "$@"
