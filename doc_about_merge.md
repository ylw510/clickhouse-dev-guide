Processors/Merges/Algorithms/MergedData.cpp：存放合并后数据。
Processors/Merges/Algorithms/MergingSortedAlgorithm.cpp：这个文件中的算子只是将多个源part中的不同Block合并到MergedData中，并不包含对相同order key行的合并操作。
Core/SortCursor.h：用来访问MergedData中数据的迭代器。
Processors/Merges/Algorithms/IMergingAlgorithm.h: merge算法的基类。
Storages/MergeTree/MergeTreeSequentialSource.cpp：merge中用来读取一个part数据的算子。
Storages/MergeTree/MergeTask.cpp：一个merge任务。其中包含了merge任务的整个执行流程。
Storages/MergeTree/MergedBlockOutputStream.h：用来将一个part的数据序列化，并刷到磁盘。
Storages/MergeTree/MergeTreeDataPartWriterWide.cpp：用来写Wide模式的part。
Storages/MergeTree/MergeTreeIndexGranularity.cpp：索引粒度，包含自适应计算索引粒度的逻辑（根据Block的rows以及uncompressed_bytes）
Storages/MergeTree/MergeTreeIndexGranularityConstant.h: 常量索引粒度，即索引粒度不会变



<horizatol, new_part> -> blocks_are_granules = false.
<horizatol, old_part> -> blocks_are_granules = false.
<vertical, old_part> -> blocks_are_granules = true.due to new_part, then index_granularity is not ok.
<vertical, new_part> -> blocks_are_granules = true.due to new_part, then index_granularity is ok.

