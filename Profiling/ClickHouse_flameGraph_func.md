# ClickHouse CPU / 内存火焰图分析指南

本文档说明如何用 `system.trace_log`、`query_profiler_cpu_time_period_ns`、`memory_profiler_sample_probability` 与 `flameGraph` 聚合函数生成 CPU 与内存火焰图（需客户端 `--allow_introspection_functions=1`）。

---

## 前置条件

- 已编译或安装的 `clickhouse` 客户端与服务端。
- 火焰图脚本：`flamegraph.pl`（例如置于 `~/Perf/`）。
- 可选：安装 `clickhouse-common-static-dbg` 等 debug 符号包，避免栈上显示地址而非符号名。

---

## 1. 准备测试数据

创建 `MergeTree` 表并写入数据（示例）：

```sql
CREATE TABLE default.hits_test
(
    `SearchPhrase` String,
    `UserID` UInt64
)
ENGINE = MergeTree
ORDER BY SearchPhrase
SETTINGS index_granularity = 8192;

INSERT INTO hits_test
SELECT
    arrayElement(['clickhouse', 'database', 'flamegraph', 'performance', ''], rand() % 5 + 1) AS SearchPhrase,
    rand() % 100000 AS UserID
FROM numbers(30000000);
```

---

## 2. CPU 采样与测试查询

开启 CPU 定时采样（单位：纳秒），执行查询并**记下服务端返回的 Query id**（下文用 `abc123` 占位）。

```sql
SET query_profiler_cpu_time_period_ns = 10000000;

SELECT *
FROM hits_test
ORDER BY rand() DESC;
```

说明：`flameGraph` 可对 CPU 轨迹使用 `arrayReverse(trace)`，便于火焰图展示习惯顺序。

---

## 3. 确认 `trace_log` 中有 CPU 记录

将 `'abc123'` 替换为实际 `query_id`：

```sql
SELECT count()
FROM system.trace_log
WHERE query_id = 'abc123'
  AND trace_type = 'CPU'
  AND event_date = today();
```

---

## 4. 生成 CPU 火焰图（SVG）

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(arrayReverse(trace)))
        FROM system.trace_log
        WHERE trace_type = 'CPU'
          AND query_id = 'abc123'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl > ~/Perf/output/flame_cpu.svg
```

输出 `flame_cpu.svg` 可用浏览器打开，支持缩放与搜索。

---

## 5.（可选）内存火焰图

### 5.1 开启内存采样并重新跑查询

提高采样概率、压低未跟踪内存阈值后**再执行一次**同类查询，记录**新的** `query_id`。

```sql
SET memory_profiler_sample_probability = 1, max_untracked_memory = 1;

SELECT SearchPhrase, COUNT(DISTINCT UserID) AS u
FROM hits_test
WHERE SearchPhrase <> ''
GROUP BY SearchPhrase
ORDER BY u DESC
LIMIT 10;
```

### 5.2 全部分配字节（按 `size`）

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(trace, size))
        FROM system.trace_log
        WHERE trace_type = 'MemorySample'
          AND query_id = 'abc123'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl --countname=bytes --color=mem > ~/Perf/output/flame_mem.svg
```

### 5.3 查询结束时仍未释放的分配（`trace`、`size`、`ptr`）

三参数形式用同一 `ptr` 配对分配（`size > 0`）与释放（`size < 0`）；**火焰图里保留的是未能配对的分配**。

应使用 **`trace_type = 'MemorySample'`**：`trace_log` 里 **`ptr` 仅对 `MemorySample` 有意义**（分配/释放采样均带指针）；`Memory` 类型记录的是另一类事件（如越过 profiler 阈值），**通常不带 `ptr`**。若误用 `'Memory'` 且 `ptr` 全为 0，`flameGraph` 会走「无指针」分支，语义与「按 ptr 配对后的未释放」不同。

可选：若要在查询结束后仍看到较多「未配对」分配（例如依赖未压缩缓存的场景），可额外打开下列缓存相关设置：

```sql
SET memory_profiler_sample_probability = 1, max_untracked_memory = 1,
    use_uncompressed_cache = 1,
    merge_tree_max_rows_to_use_cache = 100000000000,
    merge_tree_max_bytes_to_use_cache = 1000000000000;
```

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(trace, size, ptr))
        FROM system.trace_log
        WHERE trace_type = 'MemorySample'
          AND query_id = 'abc123'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl --countname=bytes --color=mem > ~/Perf/output/flame_mem_unfreed.svg
```

---

## 6. 完整 shell 示例（固定路径与 query_id）

下列命令与本地目录布局一致：`clickhouse` 客户端在 `~/ClickHouse/build_release/programs/`，火焰图脚本在 `~/Perf/`，输出在 `~/Perf/output/`。请将 `query_id` 换成你自己的查询 ID。

**CPU 火焰图 → `flame_cpu.svg`**

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(arrayReverse(trace)))
        FROM system.trace_log
        WHERE trace_type = 'CPU'
          AND query_id = 'cd9c0cd3-4ead-467a-bbb8-a9cdbc470518'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl > ~/Perf/output/flame_cpu.svg
```
<img width="1243" height="721" alt="image" src="https://github.com/user-attachments/assets/f4f17907-f03d-4e51-bbf1-e82fe43822a7" />

**内存采样（按字节聚合分配栈）→ `flame_mem.svg`**

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(trace, size))
        FROM system.trace_log
        WHERE trace_type = 'MemorySample'
          AND query_id = 'cd9c0cd3-4ead-467a-bbb8-a9cdbc470518'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl --countname=bytes --color=mem > ~/Perf/output/flame_mem.svg
```
<img width="1210" height="524" alt="image" src="https://github.com/user-attachments/assets/b4b94b80-ac19-4277-9793-2d292e7b8805" />

**仍未释放的分配（`trace`、`size`、`ptr`）→ `flame_mem_unfreed.svg`**

（筛选条件使用 `trace_type = 'MemorySample'`，与 §5.3 相同。）

```bash
~/ClickHouse/build_release/programs/clickhouse client \
    --allow_introspection_functions=1 \
    -q "SELECT arrayJoin(flameGraph(trace, size, ptr))
        FROM system.trace_log
        WHERE trace_type = 'MemorySample'
          AND query_id = 'cd9c0cd3-4ead-467a-bbb8-a9cdbc470518'
          AND event_date = today()" \
    | ~/Perf/flamegraph.pl --countname=bytes --color=mem > ~/Perf/output/flame_mem_unfreed.svg
```

---

## 要点小结

| 步骤 | 作用 |
|------|------|
| `query_profiler_cpu_time_period_ns` | 控制 CPU 栈采样间隔 |
| `trace_type = 'CPU'` + `flameGraph(arrayReverse(trace))` | CPU 火焰图 |
| `memory_profiler_sample_probability` / `max_untracked_memory` | 触发内存采样 |
| `trace_type = 'MemorySample'` + `flameGraph(trace, size)` | 内存采样：按字节汇总分配栈 |
| `trace_type = 'MemorySample'` + `flameGraph(trace, size, ptr)` | 配对 ptr 后仍为「未释放」的分配 |
| `--allow_introspection_functions=1` | 允许使用 `flameGraph` 等 introspection 函数 |

若火焰图中多为地址而非函数名：在 Linux 上一般会尝试用 ELF 调试信息把指令地址解析为符号；安装与服务端二进制匹配的 debug 符号包（或本地构建带调试信息）可改善显示。
