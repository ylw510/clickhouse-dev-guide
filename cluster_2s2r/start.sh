#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${ROOT}/env.sh"
CH="${CLICKHOUSE_BIN_DIR}"
KEEPER="${CLICKHOUSE_KEEPER}"
KEEPER_CLIENT="${CLICKHOUSE_KEEPER_CLIENT}"
SERVER="${CLICKHOUSE_SERVER}"

wait_tcp()
{
  local host="$1" port="$2" label="$3" max_sec="${4:-90}"
  local i=0
  while (( i < max_sec )); do
    if bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
      exec 3<&- 3>&-
      echo "${label} ready (${host}:${port})"
      return 0
    fi
    sleep 1
    ((++i)) || true
  done
  echo "ERROR: timeout waiting for ${label} ${host}:${port}"
  return 1
}

render_keeper_xml()
{
  local id="$1" zk_port="$2" raft1="$3" raft2="$4" raft3="$5"
  cat > "${ROOT}/keeper${id}.xml" <<EOF
<clickhouse>
    <logger>
        <level>information</level>
        <log>${ROOT}/logs/keeper${id}.log</log>
        <errorlog>${ROOT}/logs/keeper${id}.err.log</errorlog>
        <console>1</console>
    </logger>
    <listen_host>${CLUSTER_IP}</listen_host>
    <keeper_server>
        <tcp_port>${zk_port}</tcp_port>
        <server_id>${id}</server_id>
        <log_storage_path>${ROOT}/keeper${id}/log</log_storage_path>
        <snapshot_storage_path>${ROOT}/keeper${id}/snapshots</snapshot_storage_path>
        <four_letter_word_white_list>*</four_letter_word_white_list>
        <hostname_checks_enabled>false</hostname_checks_enabled>
        <coordination_settings>
            <operation_timeout_ms>10000</operation_timeout_ms>
            <session_timeout_ms>30000</session_timeout_ms>
            <min_session_timeout_ms>10000</min_session_timeout_ms>
            <snapshot_distance>10000</snapshot_distance>
            <startup_timeout>120000</startup_timeout>
            <raft_logs_level>information</raft_logs_level>
            <heart_beat_interval_ms>500</heart_beat_interval_ms>
            <election_timeout_lower_bound_ms>1000</election_timeout_lower_bound_ms>
            <election_timeout_upper_bound_ms>2000</election_timeout_upper_bound_ms>
        </coordination_settings>
        <raft_configuration>
            <server><id>1</id><hostname>${CLUSTER_IP}</hostname><port>${raft1}</port></server>
            <server><id>2</id><hostname>${CLUSTER_IP}</hostname><port>${raft2}</port><start_as_follower>true</start_as_follower></server>
            <server><id>3</id><hostname>${CLUSTER_IP}</hostname><port>${raft3}</port><start_as_follower>true</start_as_follower></server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
EOF
}

render_shard_xml()
{
  local node="$1" shard="$2" replica="$3" tcp_port="$4" http_port="$5" inter_port="$6"
  cat > "${ROOT}/node${node}.xml" <<EOF
<clickhouse>
    <logger>
        <level>information</level>
        <log>${ROOT}/logs/node${node}.log</log>
        <errorlog>${ROOT}/logs/node${node}.err.log</errorlog>
        <console>1</console>
    </logger>
    <path>${ROOT}/node${node}/data/</path>
    <tmp_path>${ROOT}/node${node}/tmp/</tmp_path>
    <user_files_path>${ROOT}/node${node}/user_files/</user_files_path>
    <format_schema_path>${ROOT}/node${node}/format_schemas/</format_schema_path>
    <users_config>${CLICKHOUSE_USERS_CONFIG}</users_config>
    <listen_host>127.0.0.1</listen_host>
    <tcp_port>${tcp_port}</tcp_port>
    <http_port>${http_port}</http_port>
    <interserver_http_host>127.0.0.1</interserver_http_host>
    <interserver_http_port>${inter_port}</interserver_http_port>
    <zookeeper>
        <node><host>${CLUSTER_IP}</host><port>9281</port></node>
        <node><host>${CLUSTER_IP}</host><port>9282</port></node>
        <node><host>${CLUSTER_IP}</host><port>9283</port></node>
    </zookeeper>
    <auxiliary_zookeepers>
        <cluster_keeper>
            <node><host>${CLUSTER_IP}</host><port>9281</port></node>
            <node><host>${CLUSTER_IP}</host><port>9282</port></node>
            <node><host>${CLUSTER_IP}</host><port>9283</port></node>
        </cluster_keeper>
    </auxiliary_zookeepers>
    <cluster_metadata>
        <keeper>cluster_keeper</keeper>
        <path>/clickhouse/clusters_metadata</path>
        <encrypted>false</encrypted>
        <key_hex>bebec0cabebec0cabebec0cabebec0ca</key_hex>
        <replica_group>group_b</replica_group>
        <imports>
            <replica_group>group_a</replica_group>
        </imports>
    </cluster_metadata>
    <named_collections_storage>
        <type>keeper</type>
        <path>/clickhouse/named_collections</path>
        <update_timeout_ms>5000</update_timeout_ms>
    </named_collections_storage>
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
    <!-- Required for create_10000_endpoints.sh timing via system.query_log. -->
    <query_log>
        <database>system</database>
        <table>query_log</table>
        <partition_by>toYYYYMM(event_date)</partition_by>
        <flush_interval_milliseconds>1000</flush_interval_milliseconds>
        <flush_on_crash>false</flush_on_crash>
    </query_log>
    <part_log>
        <database>system</database>
        <table>part_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </part_log>
    <metric_log>
        <database>system</database>
        <table>metric_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
        <collect_interval_milliseconds>1000</collect_interval_milliseconds>
    </metric_log>
    <macros>
        <shard>${shard}</shard>
        <replica>${replica}</replica>
    </macros>
    <remote_servers>
        <demo_2s2r>
            <shard>
                <internal_replication>true</internal_replication>
                <replica><host>127.0.0.1</host><port>19100</port></replica>
                <replica><host>127.0.0.1</host><port>19101</port></replica>
            </shard>
            <shard>
                <internal_replication>true</internal_replication>
                <replica><host>127.0.0.1</host><port>19102</port></replica>
                <replica><host>127.0.0.1</host><port>19103</port></replica>
            </shard>
        </demo_2s2r>
    </remote_servers>
</clickhouse>
EOF
}

mkdir -p "${ROOT}/logs"
for i in 1 2 3; do
  mkdir -p "${ROOT}/keeper${i}/log" "${ROOT}/keeper${i}/snapshots"
done
for i in 1 2 3 4; do
  mkdir -p "${ROOT}/node${i}/data" "${ROOT}/node${i}/tmp" "${ROOT}/node${i}/user_files" "${ROOT}/node${i}/format_schemas"
done

if [[ "${1:-}" == "--clean" ]]; then
  pkill -f "clickhouse-keeper.*${ROOT}/keeper" 2>/dev/null || true
  pkill -f "clickhouse-server.*${ROOT}/node" 2>/dev/null || true
  sleep 1
  rm -rf "${ROOT}/logs" \
         "${ROOT}/keeper1/log" "${ROOT}/keeper1/snapshots" \
         "${ROOT}/keeper2/log" "${ROOT}/keeper2/snapshots" \
         "${ROOT}/keeper3/log" "${ROOT}/keeper3/snapshots" \
         "${ROOT}/node1/data" "${ROOT}/node1/tmp" \
         "${ROOT}/node2/data" "${ROOT}/node2/tmp" \
         "${ROOT}/node3/data" "${ROOT}/node3/tmp" \
         "${ROOT}/node4/data" "${ROOT}/node4/tmp"
  rm -f "${ROOT}"/keeper{1,2,3}/keeper.pid "${ROOT}"/node{1,2,3,4}/server.pid
  mkdir -p "${ROOT}/logs"
  for i in 1 2 3; do
    mkdir -p "${ROOT}/keeper${i}/log" "${ROOT}/keeper${i}/snapshots"
  done
  for i in 1 2 3 4; do
    mkdir -p "${ROOT}/node${i}/data" "${ROOT}/node${i}/tmp"
  done
fi

render_keeper_xml 1 9281 9334 9335 9336
render_keeper_xml 2 9282 9334 9335 9336
render_keeper_xml 3 9283 9334 9335 9336

render_shard_xml 1 1 s1r1 19100 18223 19109
render_shard_xml 2 1 s1r2 19101 18224 19110
render_shard_xml 3 2 s2r1 19102 18225 19111
render_shard_xml 4 2 s2r2 19103 18226 19112

echo "Starting Keeper nodes..."
"${KEEPER}" --config-file="${ROOT}/keeper1.xml" --pid-file="${ROOT}/keeper1/keeper.pid" &
sleep 2
"${KEEPER}" --config-file="${ROOT}/keeper2.xml" --pid-file="${ROOT}/keeper2/keeper.pid" &
sleep 1
"${KEEPER}" --config-file="${ROOT}/keeper3.xml" --pid-file="${ROOT}/keeper3/keeper.pid" &

wait_tcp "${ZK_CHECK_HOST}" 9281 "Keeper node1 (ZK)" 120
wait_tcp "${ZK_CHECK_HOST}" 9282 "Keeper node2 (ZK)" 30
wait_tcp "${ZK_CHECK_HOST}" 9283 "Keeper node3 (ZK)" 30

"${KEEPER_CLIENT}" -h "${ZK_CHECK_HOST}" -p 9281 \
  --connection-timeout 30 --session-timeout 30 --operation-timeout 30 \
  -q "ls '/'"

echo "Starting 4 ClickHouse nodes (2 shard x 2 replica)..."
"${SERVER}" --config-file="${ROOT}/node1.xml" --pid-file="${ROOT}/node1/server.pid" &
sleep 2
"${SERVER}" --config-file="${ROOT}/node2.xml" --pid-file="${ROOT}/node2/server.pid" &
sleep 1
"${SERVER}" --config-file="${ROOT}/node3.xml" --pid-file="${ROOT}/node3/server.pid" &
sleep 1
"${SERVER}" --config-file="${ROOT}/node4.xml" --pid-file="${ROOT}/node4/server.pid" &

wait_tcp 127.0.0.1 19100 "node1" 180
wait_tcp 127.0.0.1 19101 "node2" 60
wait_tcp 127.0.0.1 19102 "node3" 60
wait_tcp 127.0.0.1 19103 "node4" 60

"${CH}/clickhouse-client" --host 127.0.0.1 --port 19100 --connect_timeout 30 -q "SELECT 'node1 OK' AS status"
"${CH}/clickhouse-client" --host 127.0.0.1 --port 19101 --connect_timeout 30 -q "SELECT 'node2 OK' AS status"
"${CH}/clickhouse-client" --host 127.0.0.1 --port 19102 --connect_timeout 30 -q "SELECT 'node3 OK' AS status"
"${CH}/clickhouse-client" --host 127.0.0.1 --port 19103 --connect_timeout 30 -q "SELECT 'node4 OK' AS status"

echo ""
echo "2 shard x 2 replica cluster is up."
echo "  cluster name: demo_2s2r"
echo "  Keepers: ${CLUSTER_IP}:9281,9282,9283"
echo "  node1..node4 native: 19100..19103"
echo "  node1..node4 HTTP:   18223..18226"
echo ""
echo "Example:"
echo "  ${CH}/clickhouse-client --port 19100 -q \"SELECT * FROM system.clusters WHERE cluster='demo_2s2r' ORDER BY shard_num, replica_num\""
