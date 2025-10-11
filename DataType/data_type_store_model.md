## Tuple


## Array


## Map


## Variant


## Dynamic
Dynamic 新增的 “半结构化数据列类型”，
用于存储 动态类型数据，即一个列中可以同时存在多种底层类型的值，例如：
```
SELECT CAST(1 AS Dynamic), CAST('abc' AS Dynamic), CAST([1,2] AS Dynamic);
```
一、整体存储模型概览

与传统的 Variant 不同：

- Variant 是静态定义的多态类型（类型集合固定）；

- Dynamic 是可增生的多态类型（运行时自动扩展类型集合）；

二者底层都依赖 ColumnVariant，但 Dynamic 在其上包了一层自描述的动态管理层。

从源码可以看到，ColumnDynamic 的存储结构其实是 一个 “ColumnVariant + 元信息层”。
```
// simplified view:
class ColumnDynamic {
    ...
    WrappedPtr variant_column;      // 实际的数据存储: ColumnVariant
    ColumnVariant* variant_column_ptr; // 为性能保存直接指针
    VariantInfo variant_info;       // 描述 Dynamic 当前所有变体的类型信息
    ...
}
```
二、内部组成结构（内存层）

核心: Dynamic 实际上 就是一个可扩展的 Variant，每种实际出现的类型（Int32、String、Array、Map、...）被封装为一个 subcolumn（子列），并且由一个 discriminator（类型标识符）记录每行属于哪个类型。
| 层级         | 对象                               | 说明                                                           |
| ---------- | -------------------------------- | ------------------------------------------------------------ |
| **顶层列对象**  | `ColumnDynamic`                  | 表面上是一个普通列                                                    |
| **内部变体列**  | `ColumnVariant`                  | 实际存储所有动态类型的数据                                                |
| **变体映射信息** | `VariantInfo`                    | 记录每个类型对应的 discriminator（编号）和类型名                              |
| **子列集合**   | `ColumnVariant::columns[]`       | 每种类型对应一个子列（`ColumnVector`, `ColumnString`, `ColumnArray`, 等） |
| **共享类型列**  | `SharedVariant` (`ColumnString`) | 当出现太多类型时，新类型序列化后以二进制格式写入此列                                   |

结构示意图：
```
ColumnDynamic
 └── ColumnVariant
      ├── discriminator[]  ← UInt8 向量，表示每行属于哪个类型
      ├── offsets[]        ← 索引偏移量
      ├── variants:
      │    ├── [0]: ColumnUInt32
      │    ├── [1]: ColumnString
      │    ├── [2]: ColumnArray(UInt32)
      │    ├── [3]: ColumnMap(String, UInt32)
      │    └── [255]: ColumnString (SharedVariant)
      └── ...
```
三、磁盘存储结构（MergeTree 层）

在 MergeTree part 文件中，Dynamic 列的物理布局是由内部的 ColumnVariant 决定的。
每个变体类型都对应独立的数据流（data stream），以类似如下命名规则存储：
```
column_name.variant_<type>.<stream_suffix>
```
如果表中插入的 Dynamic 值有 3 种类型（UInt32、String、Array(UInt32)），
那么磁盘上会出现大致这样的文件结构：
```
t/
 ├── dyn.variant_UInt32.bin
 ├── dyn.variant_UInt32.mrk3
 ├── dyn.variant_String.bin
 ├── dyn.variant_String.mrk3
 ├── dyn.variant_Array_UInt32.bin
 ├── dyn.variant_Array_UInt32.mrk3
 ├── dyn.discriminators.bin      ← 存放每行类型编号
 ├── dyn.offsets.bin             ← 行偏移表
 └── ...
```

四、动态类型扩展机制

当你插入一个新类型的值时：

void ColumnDynamic::insert(const Field & x)


内部会发生以下操作：
1. 调用 x.getType() 检查该值的类型；
2. 查询 variant_info.variant_name_to_discriminator；
3. 如果该类型已存在：
    - 直接写入对应的子列；
4. 如果该类型是新类型且还未超限：
    - 调用 addNewVariant()；
    - 在 ColumnVariant 内扩展一个新子列；
    - 更新 variant_info 映射；
5. 如果已超出 max_dynamic_types 限制：
    - 调用 insertValueIntoSharedVariant()；
    - 将值序列化成二进制写入 SharedVariant (ColumnString)。

五、SharedVariant 特殊通道

SharedVariant 是一种 “兜底” 类型：
- 类型过多或无法确定时，新值序列化进 SharedVariant；
- 序列化格式为：<type_name><binary_value>；
- 用于保证 Dynamic 列永远不会拒绝插入任何类型。

```
insert 1 → UInt32
insert 'abc' → String
insert map('k',1) → 新类型 Map(String,UInt32)
insert tuple(1,2) → 超过限制 → SharedVariant 存为 "Tuple(UInt32,UInt32)|<bin>"
```
六、示例
1. 表
```
CREATE TABLE default.dynamic_merge_tree_test
(
    `id` UInt64,
    `name` String,
    `dyn` Dynamic,
    `ts` DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (id, ts)
SETTINGS index_granularity = 8192
```
2. 写入数据
```
INSERT INTO default.dynamic_merge_tree_test (id, name, dyn)
SELECT
    number AS id,
    concat('user_', toString(number)) AS name,
    multiIf(
        (rand() % 3) = 0, CAST(toUInt32(rand() % 1000) AS Dynamic),
        (rand() % 3) = 1, CAST(concat('str_', toString(rand() % 1000)) AS Dynamic),
        CAST(arrayMap(x -> toUInt32(x % 1000), range((rand() % 5) + 1)) AS Dynamic)
    ) AS dyn
FROM numbers(1000000);
```

查看wide part的磁盘文件
```
root@ubantu64:~/work/ClickHouse/build/programs/store/a76/a7609f34-18c3-419c-a364-9f7d44d52e29/all_2_2_0# ll
total 12292
drwxr-x--- 2 root root    4096 Oct 11 18:13  ./
drwxr-x--- 5 root root    4096 Oct 11 18:13  ../
-rw-r----- 1 root root    1136 Oct 11 18:13  checksums.txt
-rw-r----- 1 root root      91 Oct 11 18:13  columns.txt
-rw-r----- 1 root root     307 Oct 11 18:13  columns_substreams.txt
-rw-r----- 1 root root       7 Oct 11 18:13  count.txt
-rw-r----- 1 root root      10 Oct 11 18:13  default_compression_codec.txt
-rw-r----- 1 root root  924507 Oct 11 18:13 'dyn.Array(UInt32).bin'
-rw-r----- 1 root root     466 Oct 11 18:13 'dyn.Array(UInt32).cmrk2'
-rw-r----- 1 root root  811132 Oct 11 18:13 'dyn.Array(UInt32).size0.bin'
-rw-r----- 1 root root     464 Oct 11 18:13 'dyn.Array(UInt32).size0.cmrk2'
-rw-r----- 1 root root       0 Oct 11 18:13  dyn.SharedVariant.bin
-rw-r----- 1 root root      56 Oct 11 18:13  dyn.SharedVariant.cmrk2
-rw-r----- 1 root root 1127869 Oct 11 18:13  dyn.String.bin
-rw-r----- 1 root root     426 Oct 11 18:13  dyn.String.cmrk2
-rw-r----- 1 root root  841164 Oct 11 18:13  dyn.UInt32.bin
-rw-r----- 1 root root     408 Oct 11 18:13  dyn.UInt32.cmrk2
-rw-r----- 1 root root      69 Oct 11 18:13  dyn.dynamic_structure.bin
-rw-r----- 1 root root      63 Oct 11 18:13  dyn.dynamic_structure.cmrk2
-rw-r----- 1 root root  565564 Oct 11 18:13  dyn.variant_discr.bin
-rw-r----- 1 root root     268 Oct 11 18:13  dyn.variant_discr.cmrk2
-rw-r----- 1 root root 4004915 Oct 11 18:13  id.bin
-rw-r----- 1 root root     415 Oct 11 18:13  id.cmrk2
-rw-r----- 1 root root       1 Oct 11 18:13  metadata_version.txt
-rw-r----- 1 root root 4188196 Oct 11 18:13  name.bin
-rw-r----- 1 root root     415 Oct 11 18:13  name.cmrk2
-rw-r----- 1 root root     177 Oct 11 18:13  primary.cidx
-rw-r----- 1 root root     229 Oct 11 18:13  serialization.json
-rw-r----- 1 root root   18042 Oct 11 18:13  ts.bin
-rw-r----- 1 root root     375 Oct 11 18:13  ts.cmrk2

```
## Json



## Nullable
