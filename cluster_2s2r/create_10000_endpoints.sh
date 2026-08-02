#!/usr/bin/env bash
# Create many SQL catalog ENDPOINTs via clickhouse-client and report elapsed time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_SH="${ROOT}/client.sh"

# Default: 10000 endpoints (1万). Override with ENDPOINT_COUNT.
ENDPOINT_COUNT="${ENDPOINT_COUNT:-1000}"
# Which cluster node to send DDL to (see client.sh).
NODE="${NODE:-1}"
# Name prefix for generated endpoints.
NAME_PREFIX="${NAME_PREFIX:-bench_ep_}"
# Base TCP port; endpoint i uses BASE_PORT + i.
BASE_PORT="${BASE_PORT:-30000}"
# Print progress every N endpoints (0 = disable).
PROGRESS_EVERY="${PROGRESS_EVERY:-500}"
VERBOSE="${VERBOSE:-0}"
# Print per-query duration from system.query_log after each CREATE (1=on, 0=off).
PRINT_QUERY_LOG_TIME="${PRINT_QUERY_LOG_TIME:-1}"
# Host stored in endpoint PROPERTIES.
ENDPOINT_HOST="${ENDPOINT_HOST:-127.0.0.1}"
ENDPOINT_USER="${ENDPOINT_USER:-default}"

usage()
{
  cat <<EOF
Usage: $(basename "$0") [options]

Create ENDPOINT_COUNT SQL catalog endpoints using clickhouse-client (via client.sh)
and print total elapsed time. When enabled, also prints each CREATE duration from
system.query_log (query_duration_ms).

Options:
  -n, --count N          number of endpoints (default: ${ENDPOINT_COUNT})
  --node N               ClickHouse node 1-4 (default: ${NODE})
  --prefix NAME          endpoint name prefix (default: ${NAME_PREFIX})
  --base-port PORT       first port = BASE_PORT + 1 (default: ${BASE_PORT})
  --progress-every N     progress line every N endpoints (default: ${PROGRESS_EVERY})
  --no-query-log-time    do not query system.query_log for per-CREATE duration
  -v, --verbose          print clickhouse-client errors
  -h, --help             show this help

Environment (same as above):
  ENDPOINT_COUNT, NODE, NAME_PREFIX, BASE_PORT, PROGRESS_EVERY,
  PRINT_QUERY_LOG_TIME, ENDPOINT_HOST, ENDPOINT_USER, CLICKHOUSE_BIN_DIR, CH_HOST

Examples:
  $(basename "$0")
  $(basename "$0") --count 1000 --node 1
  ENDPOINT_COUNT=100 $(basename "$0") --progress-every 10

Verify after run:
  ./client.sh 1 -q "SELECT count() FROM system.endpoints WHERE name LIKE '${NAME_PREFIX}%'"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--count)
      ENDPOINT_COUNT="$2"
      shift 2
      ;;
    --node)
      NODE="$2"
      shift 2
      ;;
    --prefix)
      NAME_PREFIX="$2"
      shift 2
      ;;
    --base-port)
      BASE_PORT="$2"
      shift 2
      ;;
    --progress-every)
      PROGRESS_EVERY="$2"
      shift 2
      ;;
    --no-query-log-time)
      PRINT_QUERY_LOG_TIME=0
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${ENDPOINT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${ENDPOINT_COUNT}" -lt 1 ]]; then
  echo "ENDPOINT_COUNT must be a positive integer, got: ${ENDPOINT_COUNT}" >&2
  exit 1
fi

if [[ ! -f "${CLIENT_SH}" ]]; then
  echo "Missing client wrapper: ${CLIENT_SH}" >&2
  exit 1
fi

run_query()
{
  bash "${CLIENT_SH}" "${NODE}" -q "$1"
}

run_query_with_id()
{
  # $1 = query_id, $2 = SQL
  bash "${CLIENT_SH}" "${NODE}" --query_id="$1" -q "$2"
}

pad_index()
{
  # Zero-pad so lexical order matches numeric order up to 99999999.
  printf '%08d' "$1"
}

# Look up query_duration_ms from system.query_log for a given query_id.
# Flushes query_log first; retries briefly because the flush can race.
query_log_duration_ms()
{
  local qid="$1"
  local attempt
  local duration=""

  run_query "SYSTEM FLUSH LOGS query_log" >/dev/null 2>&1 || true

  for attempt in 1 2 3 4 5; do
    # QueryFinish for success; Exception* for failed CREATE ENDPOINT.
    duration="$(
      run_query "
        SELECT query_duration_ms
        FROM system.query_log
        WHERE query_id = '${qid}'
          AND type IN ('QueryFinish', 'ExceptionWhileProcessing', 'ExceptionBeforeStart')
        ORDER BY event_time_microseconds DESC
        LIMIT 1
        FORMAT TabSeparated
      " 2>/dev/null || true
    )"
    if [[ -n "${duration}" ]]; then
      echo "${duration}"
      return 0
    fi
    sleep 0.05
  done

  echo ""
  return 1
}

echo "Creating ${ENDPOINT_COUNT} endpoints on node ${NODE} (prefix=${NAME_PREFIX}, ports=$((BASE_PORT + 1))..=$((BASE_PORT + ENDPOINT_COUNT)))"
if [[ "${PRINT_QUERY_LOG_TIME}" == 1 ]]; then
  echo "Per-CREATE duration will be read from system.query_log (query_duration_ms)."
fi

mkdir -p "${ROOT}/tmp"
start_ts="$(date +%s.%N)"
created=0
failed=0
sum_duration_ms=0
min_duration_ms=""
max_duration_ms=""
timed_count=0

for ((i = 1; i <= ENDPOINT_COUNT; ++i)); do
  idx="$(pad_index "${i}")"
  name="${NAME_PREFIX}${idx}"
  port=$((BASE_PORT + i))
  # Stable, unique query_id so we can join back to system.query_log.
  qid="create_endpoint_${NAME_PREFIX}${idx}_$$"
  sql="CREATE ENDPOINT IF NOT EXISTS ${name} PROPERTIES (host = '${ENDPOINT_HOST}', port = ${port}, user = '${ENDPOINT_USER}')"

  err_file="${ROOT}/tmp/create_endpoints_err.$$"
  if run_query_with_id "${qid}" "${sql}" >"${err_file}" 2>&1; then
    created=$((created + 1))
    status="ok"
  else
    failed=$((failed + 1))
    status="fail"
    echo "FAILED: ${name} (port ${port})" >&2
    if [[ "${VERBOSE}" == 1 ]] || [[ "${failed}" -le 3 ]]; then
      sed 's/^/  /' "${err_file}" >&2
    fi
  fi
  rm -f "${err_file}"

  if [[ "${PRINT_QUERY_LOG_TIME}" == 1 ]]; then
    duration_ms="$(query_log_duration_ms "${qid}" || true)"
    if [[ -n "${duration_ms}" ]]; then
      echo "[query_log] ${i}/${ENDPOINT_COUNT} ${name} status=${status} query_id=${qid} query_duration_ms=${duration_ms}"
      sum_duration_ms=$((sum_duration_ms + duration_ms))
      timed_count=$((timed_count + 1))
      if [[ -z "${min_duration_ms}" ]] || [[ "${duration_ms}" -lt "${min_duration_ms}" ]]; then
        min_duration_ms="${duration_ms}"
      fi
      if [[ -z "${max_duration_ms}" ]] || [[ "${duration_ms}" -gt "${max_duration_ms}" ]]; then
        max_duration_ms="${duration_ms}"
      fi
    else
      echo "[query_log] ${i}/${ENDPOINT_COUNT} ${name} status=${status} query_id=${qid} query_duration_ms=<not found>"
    fi
  fi

  if [[ "${PROGRESS_EVERY}" -gt 0 ]] && (( i % PROGRESS_EVERY == 0 )); then
    now_ts="$(date +%s.%N)"
    elapsed="$(awk -v s="${start_ts}" -v e="${now_ts}" 'BEGIN { printf "%.2f", e - s }')"
    echo "[progress] ${i}/${ENDPOINT_COUNT} created=${created} failed=${failed} elapsed=${elapsed}s"
  fi
done

end_ts="$(date +%s.%N)"
elapsed="$(awk -v s="${start_ts}" -v e="${end_ts}" 'BEGIN { printf "%.3f", e - s }')"
rate="$(awk -v n="${created}" -v t="${elapsed}" 'BEGIN { if (t > 0) printf "%.2f", n / t; else print "0" }')"

echo
echo "=== done ==="
echo "requested : ${ENDPOINT_COUNT}"
echo "created   : ${created}"
echo "failed    : ${failed}"
echo "elapsed   : ${elapsed}s"
echo "throughput: ${rate} endpoints/s"

if [[ "${PRINT_QUERY_LOG_TIME}" == 1 ]] && [[ "${timed_count}" -gt 0 ]]; then
  avg_duration_ms="$(awk -v s="${sum_duration_ms}" -v n="${timed_count}" 'BEGIN { printf "%.2f", s / n }')"
  echo
  echo "=== query_log timing (CREATE ENDPOINT) ==="
  echo "samples   : ${timed_count}"
  echo "min_ms    : ${min_duration_ms}"
  echo "max_ms    : ${max_duration_ms}"
  echo "avg_ms    : ${avg_duration_ms}"
  echo "sum_ms    : ${sum_duration_ms}"
fi

echo
echo "Verifying endpoint count in system.endpoints ..."
verify_sql="SELECT count() AS c FROM system.endpoints WHERE name LIKE '${NAME_PREFIX}%'"
run_query "${verify_sql}"

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
