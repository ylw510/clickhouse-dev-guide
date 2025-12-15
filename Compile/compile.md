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

## 最大编译线程的限制
ClickHouse的编译线程数，并不是你指定多少线程就用多少线程来进行编译的：
```
ninja -j 32
```
例如，即使你指定了`-j32`，用32线程来进行编译，但是实际的线程数据由以下参数确定：
- PARALLEL_COMPILE_JOBS
- PARALLEL_LINK_JOBS
- MAX_COMPILER_MEMORY
- MAX_LINKER_MEMORY

顶层的`CMakeLists.txt`中包含`MAX_COMPILER_MEMORY`，`MAX_LINKER_MEMORY`的设置逻辑。
1. 首先使用`cmake_host_system_information`查看当前系统的可用内存，并将其值赋予`AVAILABLE_PHYSICAL_MEMORY`：
```
cmake_host_system_information(RESULT AVAILABLE_PHYSICAL_MEMORY QUERY AVAILABLE_PHYSICAL_MEMORY) # Not available under freebsd
```
2. 当系统可用内存大于8GB或无法检测时，启用编译器的`-pipe`选项以减少磁盘I/O（减少临时文件），但会增加内存使用。
```
if(NOT AVAILABLE_PHYSICAL_MEMORY OR AVAILABLE_PHYSICAL_MEMORY GREATER 8000)
    # Less `/tmp` usage, more RAM usage.
    option(COMPILER_PIPE "-pipe compiler option" ON)
endif()
```
3. 根据是否启用-pipe编译器选项，设置编译器和链接器的最大内存限制：启用时编译器限制为2.5GB，否则1.5GB；链接器统一限制为5GB。
```
if(COMPILER_PIPE)
    set(MAX_COMPILER_MEMORY 2500)
else()
    set(MAX_COMPILER_MEMORY 1500)
endif()
set(MAX_LINKER_MEMORY 5000)
include(cmake/limit_jobs.cmake)
```

`cmake/limit_jobs.cmake`中的逻辑如下：
```
# Limit compiler/linker job concurrency to avoid OOMs on subtrees where compilation/linking is memory-intensive.
#
# Usage from CMake:
#    set (MAX_COMPILER_MEMORY 2000 CACHE INTERNAL "") # megabyte
#    set (MAX_LINKER_MEMORY 5000 CACHE INTERNAL "") # megabyte
#    include (cmake/limit_jobs.cmake)
#
# (bigger values mean fewer jobs)

cmake_host_system_information(RESULT TOTAL_PHYSICAL_MEMORY QUERY TOTAL_PHYSICAL_MEMORY)
cmake_host_system_information(RESULT NUMBER_OF_LOGICAL_CORES QUERY NUMBER_OF_LOGICAL_CORES)

# Set to disable the automatic job-limiting
option(PARALLEL_COMPILE_JOBS "Maximum number of concurrent compilation jobs" OFF)
option(PARALLEL_LINK_JOBS "Maximum number of concurrent link jobs" OFF)

if (NOT PARALLEL_COMPILE_JOBS AND MAX_COMPILER_MEMORY)
    math(EXPR PARALLEL_COMPILE_JOBS ${TOTAL_PHYSICAL_MEMORY}/${MAX_COMPILER_MEMORY})

    if (NOT PARALLEL_COMPILE_JOBS)
        set (PARALLEL_COMPILE_JOBS 1)
    endif ()
    if (PARALLEL_COMPILE_JOBS LESS NUMBER_OF_LOGICAL_CORES)
        message("The auto-calculated compile jobs limit (${PARALLEL_COMPILE_JOBS}) underutilizes CPU cores (${NUMBER_OF_LOGICAL_CORES}). Set PARALLEL_COMPILE_JOBS to override.")
    endif()
endif ()

if (NOT PARALLEL_LINK_JOBS AND MAX_LINKER_MEMORY)
    math(EXPR PARALLEL_LINK_JOBS ${TOTAL_PHYSICAL_MEMORY}/${MAX_LINKER_MEMORY})

    if (NOT PARALLEL_LINK_JOBS)
        set (PARALLEL_LINK_JOBS 1)
    endif ()
    if (PARALLEL_LINK_JOBS LESS NUMBER_OF_LOGICAL_CORES)
        message("The auto-calculated link jobs limit (${PARALLEL_LINK_JOBS}) underutilizes CPU cores (${NUMBER_OF_LOGICAL_CORES}). Set PARALLEL_LINK_JOBS to override.")
    endif()
endif ()
```
1. 计算原理：
```
math(EXPR PARALLEL_COMPILE_JOBS ${TOTAL_PHYSICAL_MEMORY}/${MAX_COMPILER_MEMORY})
编译作业数 = 总内存 / MAX_COMPILER_MEMORY（默认2GB或1.5GB）

链接作业数 = 总内存 / MAX_LINKER_MEMORY（默认5GB）
```
2. 优先级规则：
用户显式设置优先：如果设置了PARALLEL_COMPILE_JOBS/PARALLEL_LINK_JOBS，则使用用户值

自动计算次之：未设置时根据内存限制自动计算

确保至少1个作业：计算结果为0时设为1

总结ck通过内存除以单作业内存上限自动计算安全的并行作业数，优先防止OOM而非最大化CPU利用率。我们个人编译可根据实际cpu核心和内存，调大以下参数：
```
PARALLEL_COMPILE_JOBS
PARALLEL_LINK_JOBS
```
