## ReadTask
`MergeTreeReadTask`用来表示一个read任务

### estimateNumRows
先基于字节配额和单列大小估计行数，再保证不低于索引粒度粒度，最后结合当前未读行数和索引粒度做精确调整。

这样能保证读取的行数既满足字节和列大小限制，也不会读取过少数据，保持效率。

如果没有预测器则退化为简单的最大块行数限制。
之后取`max_block_size_rows`和`recommended_rows`的最小值，`max_block_size_rows`默认值为`65409`
```
  UInt64 recommended_rows = estimateNumRows();
  UInt64 rows_to_read = std::max(static_cast<UInt64>(1), std::min(block_size_params.max_block_size_rows, recommended_rows));
```

## MergeTreeReadPool

`fillPerThreadInfo`填充每一个线程的读取任务，将经过分区，minmax裁剪之后的所有part的总mark均匀的分配到每个线程。

## MergeTreeInOrderSelectAlgorithm
顺序读取mark

## MergeTreeInReverseOrderSelectAlgorithm
逆序读取mark
