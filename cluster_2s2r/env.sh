# Shared defaults for cluster_2s2r scripts.
# Override any variable before sourcing, or export it in the environment.
# Example:
#   CLICKHOUSE_BIN_DIR=/path/to/programs ./start.sh
#   CLUSTER_IP=127.0.0.1 ./keeper-client.sh

# Directory that contains clickhouse-server / clickhouse-client / clickhouse-keeper.
CLICKHOUSE_BIN_DIR="${CLICKHOUSE_BIN_DIR:-/root/work/ClickHouse/build_release/programs}"

# users.xml used by servers (usually next to the binaries).
CLICKHOUSE_USERS_CONFIG="${CLICKHOUSE_USERS_CONFIG:-${CLICKHOUSE_BIN_DIR}/users.xml}"

# Keepers bind / advertise on this host/IP.
CLUSTER_IP="${CLUSTER_IP:-192.168.153.128}"

# Host used when probing Keeper readiness (defaults to CLUSTER_IP).
ZK_CHECK_HOST="${ZK_CHECK_HOST:-${CLUSTER_IP}}"

# clickhouse-client host for node connections.
CH_HOST="${CH_HOST:-127.0.0.1}"

# clickhouse-keeper-client host (defaults to CLUSTER_IP).
KEEPER_CLIENT_HOST="${KEEPER_CLIENT_HOST:-${CLUSTER_IP}}"

# Derived binary paths.
CLICKHOUSE_SERVER="${CLICKHOUSE_SERVER:-${CLICKHOUSE_BIN_DIR}/clickhouse-server}"
CLICKHOUSE_CLIENT="${CLICKHOUSE_CLIENT:-${CLICKHOUSE_BIN_DIR}/clickhouse-client}"
CLICKHOUSE_KEEPER="${CLICKHOUSE_KEEPER:-${CLICKHOUSE_BIN_DIR}/clickhouse-keeper}"
CLICKHOUSE_KEEPER_CLIENT="${CLICKHOUSE_KEEPER_CLIENT:-${CLICKHOUSE_BIN_DIR}/clickhouse-keeper-client}"
