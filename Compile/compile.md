## cmake构建选项
`-DENABLE_RUST`用于控制是否构建rust相关的模块，例如`chdig`组件等。

`-DENABLE_JEMALLOC` 用于控制是否使用jemalloc内存分配器。

`-DSANITIZE` 用于控制是否开启ASAN的某个模块。

示例如下，表示不开启rust模块，不适用jemalloc，使用ASANA的内存模块来构建：
```
cmake -DENABLE_JEMALLOC=0 -DSANITIZE=memory -DENABLE_RUST=0 ..
```

## ninja 命令
ClickHouse默认使用Ninja编译，cmake 选项`-G`来控制。

只构建单元测试模块：
```
ninja unit_tests_dbms
```
