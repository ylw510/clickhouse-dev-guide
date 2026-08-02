# cluster_2s2r — SQL cluster metadata 测试脚本

对应 `start.sh` 启动的 4 节点拓扑：

| Node | Shard | Replica | Native 端口 |
|------|-------|---------|-------------|
| node1 | 1 | s1r1 | 19100 |
| node2 | 1 | s1r2 | 19101 |
| node3 | 2 | s2r1 | 19102 |
| node4 | 2 | s2r2 | 19103 |

在任意 node 上执行以下 SQL（建议从 node1 开始）。

```bash
cd /root/ClickHouse/tmp/cluster_2s2r
./client.sh 1
```

---

## 1. 创建 4 个 endpoint

```sql
CREATE ENDPOINT IF NOT EXISTS s1r1
PROPERTIES (
    host = '127.0.0.1',
    port = 19100,
    user = 'default'
);

CREATE ENDPOINT IF NOT EXISTS s1r2
PROPERTIES (
    host = '127.0.0.1',
    port = 19101,
    user = 'default'
);

CREATE ENDPOINT IF NOT EXISTS s2r1
PROPERTIES (
    host = '127.0.0.1',
    port = 19102,
    user = 'default'
);

CREATE ENDPOINT IF NOT EXISTS s2r2
PROPERTIES (
    host = '127.0.0.1',
    port = 19103,
    user = 'default'
);
```

验证：

```sql
SELECT name, host, port, user, bound_shards
FROM system.endpoints
ORDER BY name;
```

---

## 2. 创建 2 个 shard

shard1 引用 `s1r1`、`s1r2`；shard2 引用 `s2r1`、`s2r2`。

```sql
CREATE SHARD IF NOT EXISTS shard_1
REPLICA (s1r1, s1r2)
PROPERTIES (
    weight = 1,
    internal_replication = true
);

CREATE SHARD IF NOT EXISTS shard_2
REPLICA (s2r1, s2r2)
PROPERTIES (
    weight = 1,
    internal_replication = true
);
```

验证：

```sql
SELECT name, endpoints, weight, internal_replication, referenced_by_clusters
FROM system.shards
ORDER BY name;
```

---

## 3. 创建 cluster

引用上面两个 shard：

```sql
CREATE CLUSTER IF NOT EXISTS demo_sql
(shard_1, shard_2)
PROPERTIES (
    allow_distributed_ddl_queries = true
);
```

验证：

```sql
SHOW CREATE CLUSTER demo_sql;

SELECT *
FROM system.shards
ORDER BY name;

SELECT name, host, port, bound_shards
FROM system.endpoints
ORDER BY name;
```

---

## 4. 一键复制版（顺序执行）

```sql
CREATE ENDPOINT IF NOT EXISTS s1r1 PROPERTIES (host = '127.0.0.1', port = 19100, user = 'default');
CREATE ENDPOINT IF NOT EXISTS s1r2 PROPERTIES (host = '127.0.0.1', port = 19101, user = 'default');
CREATE ENDPOINT IF NOT EXISTS s2r1 PROPERTIES (host = '127.0.0.1', port = 19102, user = 'default');
CREATE ENDPOINT IF NOT EXISTS s2r2 PROPERTIES (host = '127.0.0.1', port = 19103, user = 'default');

CREATE SHARD IF NOT EXISTS shard_1 REPLICA (s1r1, s1r2) PROPERTIES (weight = 1, internal_replication = true);
CREATE SHARD IF NOT EXISTS shard_2 REPLICA (s2r1, s2r2) PROPERTIES (weight = 1, internal_replication = true);

CREATE CLUSTER IF NOT EXISTS demo_sql (shard_1, shard_2) PROPERTIES (allow_distributed_ddl_queries = true);
```

---

## 5. 一键复制版（删除，逆序执行）

先删 cluster，再删 shard，最后删 endpoint：

```sql
DROP CLUSTER IF EXISTS demo_sql;

DROP SHARD IF EXISTS shard_1;
DROP SHARD IF EXISTS shard_2;

DROP ENDPOINT IF EXISTS s1r1;
DROP ENDPOINT IF EXISTS s1r2;
DROP ENDPOINT IF EXISTS s2r1;
DROP ENDPOINT IF EXISTS s2r2;
```

验证：

```sql
SELECT name FROM system.endpoints ORDER BY name;
SELECT name FROM system.shards ORDER BY name;
```

---

## 6. Keeper 路径（`encrypted=false` 时可读）

```bash
./keeper-client.sh 1 -q "ls '/clickhouse/clusters_metadata/group_b/metadata/endpoints'"
./keeper-client.sh 1 -q "ls '/clickhouse/clusters_metadata/group_b/metadata/shards'"
./keeper-client.sh 1 -q "ls '/clickhouse/clusters_metadata/group_b/metadata/clusters'"
```

---

## 7. 清理后重测

若之前用加密配置写过 Keeper，建议 clean 后重跑：

```bash
./stop.sh
./start.sh --clean
```

然后再执行第 4 节的一键 SQL。
