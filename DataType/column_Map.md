<!-- TOC -->

## 一、总体设计思想
在 ClickHouse 中，Map(K, V) 并不是一个独立的底层存储结构，
而是通过组合更基础的列类型实现的：
```
Map(K, V) = Array(Tuple(key, value))
```
即：
- 每一行的 Map 实际上是一个 数组（Array）；
- 数组的每个元素是一个 二元组 (key, value)；
- 整个列在物理上存储为：
  - 一个 ColumnArray（保存每行数组的中元素个数）
  - 其内部嵌套的是一个 ColumnTuple，包含：
    - ColumnVector<KeyType>：所有 key 顺序存储
    - ColumnVector<ValueType>：所有 value 顺序存储

其中，`nested`即为：ColumnArray(ColumnTuple(keys, values))。
```
/** Column, that stores a nested Array(Tuple(key, value)) column.
 */
class ColumnMap final : public COWHelper<IColumnHelper<ColumnMap>, ColumnMap>
{
private:
    friend class COWHelper<IColumnHelper<ColumnMap>, ColumnMap>;

    WrappedPtr nested;
...
```
示例：
在内存布局中，它像这样：
```
Row1:  [(k1,v1), (k2,v2)]
Row2:  [(k3,v3)]
Row3:  [(k4,v4), (k5,v5), (k6,v6)]
```
会被拆成（）：
| 数据结构        | 内容示例                     |
| ----------- | ------------------------ |
| `keys` 列    | [k1, k2, k3, k4, k5, k6] |
| `values` 列  | [v1, v2, v3, v4, v5, v6] |
| `offsets` 列 | [2, 1, 3]  ← 表示每行元素个数 |

一般来说offsets列在磁盘中存储的列名为`size0`。
## 二、Map的Wide存储模型测试
```
1. CREATE TABLE default.test
(
    `c1` Int32,
    `c2` Map(String, Int32)
)
ENGINE = MergeTree
ORDER BY c1
SETTINGS index_granularity = 8192
```
2. 写入100W随机数据， key在[k0 - k9]
```
INSERT INTO test
SELECT
    number AS c1,
    map(
        concat('k', toString(rand() % 10)),
        rand() % 1000
    ) AS c2
FROM numbers(100000);
```
3. 查看数据存储路径
```
select table,data_paths from system.tables where table = 'test'
```
4. Part的磁盘布局
```
root@ubantu64:~/work/ClickHouse/build/programs/store/9d8/9d8c8586-ca90-4ae1-9e6a-cb1188d33c3a/all_2_2_0# cat count.txt
1000000
root@ubantu64:~/work/ClickHouse/build/programs/store/9d8/9d8c8586-ca90-4ae1-9e6a-cb1188d33c3a/all_2_2_0# ll
total 8228
drwxr-x--- 2 root root    4096 Oct 14 14:50 ./
drwxr-x--- 5 root root    4096 Oct 14 14:50 ../
-rw-r----- 1 root root 4017256 Oct 14 14:50 c1.bin
-rw-r----- 1 root root     439 Oct 14 14:50 c1.cmrk2
-rw-r----- 1 root root 1432310 Oct 14 14:50 c2%2Ekeys.bin
-rw-r----- 1 root root     342 Oct 14 14:50 c2%2Ekeys.cmrk2
-rw-r----- 1 root root 2875686 Oct 14 14:50 c2%2Evalues.bin
-rw-r----- 1 root root     424 Oct 14 14:50 c2%2Evalues.cmrk2
-rw-r----- 1 root root   36169 Oct 14 14:50 c2.size0.bin
-rw-r----- 1 root root     323 Oct 14 14:50 c2.size0.cmrk2
-rw-r----- 1 root root     559 Oct 14 14:50 checksums.txt
-rw-r----- 1 root root      72 Oct 14 14:50 columns.txt
-rw-r----- 1 root root     139 Oct 14 14:50 columns_substreams.txt
-rw-r----- 1 root root       7 Oct 14 14:50 count.txt
-rw-r----- 1 root root      10 Oct 14 14:50 default_compression_codec.txt
-rw-r----- 1 root root       1 Oct 14 14:50 metadata_version.txt
-rw-r----- 1 root root     267 Oct 14 14:50 primary.cidx
-rw-r----- 1 root root      93 Oct 14 14:50 serialization.json
```
- 其中 `columns_substreams.txt`，记录了每个列的信息及其子列
```
root@ubantu64:~/work/ClickHouse/build/programs/store/9d8/9d8c8586-ca90-4ae1-9e6a-cb1188d33c3a/all_2_2_0# cat columns_substreams.txt
columns substreams version: 1
2 columns:
1 substreams for column `c1`:
        c1
3 substreams for column `c2`:
        c2.size0
        c2%2Ekeys
        c2%2Evalues
```
## 常见问题
1. 对于每行的重复key，他都会进行存储.

1️⃣ 创建测试表
```
DROP TABLE IF EXISTS test_map_dup;

CREATE TABLE test_map_dup
(
    id UInt32,
    m Map(String, Int32)
)
ENGINE = MergeTree()
ORDER BY id;
```
2️⃣ 插入包含重复 key 的数据
```
INSERT INTO test_map_dup VALUES
(1, map('a', 10, 'b', 20, 'a', 30)),
(2, map('x', 5, 'y', 6, 'x', 7, 'x', 8)),
(3, map('p', 100)),
(4, map('q', 1, 'r', 2, 'q', 3));
```
3️⃣ 查询每行的所有 key
```
SELECT id, mapKeys(m) AS keys
FROM test_map_dup
ORDER BY id;
```
结果如下：
```
ubantu64 :) SELECT id, mapKeys(m) AS keys
FROM test_map_dup
ORDER BY id;

SELECT
    id,
    mapKeys(m) AS keys
FROM test_map_dup
ORDER BY id ASC

Query id: 13d94ac8-845c-4238-8d7d-3473f5a2d6e4

   ┌─id─┬─keys──────────────┐
1. │  1 │ ['a','b','a']     │
2. │  2 │ ['x','y','x','x'] │
3. │  3 │ ['p']             │
4. │  4 │ ['q','r','q']     │
   └────┴───────────────────┘

4 rows in set. Elapsed: 0.002 sec.
```
2. 查询某个 key 的值（默认取第一个匹配）
```
ubantu64 :) SELECT
    id,
    m['a'] AS value_a,
    m['x'] AS value_x,
    m['q'] AS value_q
FROM test_map_dup
ORDER BY id;


SELECT
    id,
    m['a'] AS value_a,
    m['x'] AS value_x,
    m['q'] AS value_q
FROM test_map_dup
ORDER BY id ASC

Query id: 823d516d-ba8f-438d-a587-34d75f4805fd

   ┌─id─┬─value_a─┬─value_x─┬─value_q─┐
1. │  1 │      10 │       0 │       0 │
2. │  2 │       0 │       5 │       0 │
3. │  3 │       0 │       0 │       0 │
4. │  4 │       0 │       0 │       1 │
   └────┴─────────┴─────────┴─────────┘

4 rows in set. Elapsed: 0.002 sec.
```
3. 使用`列名.keys` `列名.values`可以直接查看所有的key和value值

```
ubantu64 :) SELECT
    c1,
    c2.keys AS keys_col,
    c2.values AS values_col
FROM test
ORDER BY c1 limit 10;

SELECT
    c1,
    c2.keys AS keys_col,
    c2.values AS values_col
FROM test
ORDER BY c1 ASC
LIMIT 10

Query id: 15f2a030-a27c-4661-a89e-95a4895fdbe4

    ┌─c1─┬─keys_col─┬─values_col─┐
 1. │  0 │ ['k3']   │ [93]       │
 2. │  0 │ ['k9']   │ [29]       │
 3. │  1 │ ['k5']   │ [805]      │
 4. │  1 │ ['k1']   │ [251]      │
 5. │  2 │ ['k4']   │ [384]      │
 6. │  2 │ ['k5']   │ [265]      │
 7. │  3 │ ['k5']   │ [705]      │
 8. │  3 │ ['k0']   │ [830]      │
 9. │  4 │ ['k9']   │ [449]      │
10. │  4 │ ['k8']   │ [618]      │
    └────┴──────────┴────────────┘

10 rows in set. Elapsed: 0.002 sec. Processed 16.38 thousand rows, 557.06 KB (6.90 million rows/s., 234.61 MB/s.)
Peak memory usage: 1.49 MiB.
```
## 总结
ClickHouse 的 Map 列并非原生哈希表结构，而是通过 Array(Tuple(key, value)) 实现的逻辑映射。
ColumnMap在底层无法进行O(1)的访问，但是ClickHouse也实现了一些逻辑映射函数，例如可以直接使用map[key]的方式来访问map的key（底层实现是遍历）。
