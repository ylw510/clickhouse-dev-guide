### 如何不开启外部库

option(ENABLE_LIBRARIES "Enable all external libraries by default" ON)
```
timeout -v 45m gdb -batch \
  -ex 'handle all nostop' \
  -ex 'set print thread-events off' \
  -ex run \
  -ex bt \
  -ex 'thread apply all bt' \
  --args ./unit_tests_dbms --gtest_filter=T64Test.*
```
```
cmake .. \
  -DENABLE_TESTS=1 \
  -DENABLE_LIBRARIES=0 \
  -DENABLE_CCACHE=0 \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=clang-17 \
  -DCMAKE_CXX_COMPILER=clang++-17 \
  -GNinja
```
  
开启单元测试, 默认开启：
```
option(ENABLE_TESTS "Provide unit_test_dbms target with Google.Test unit tests" ON)
```

### 如何在ClickHouse中运行GTest：
使用`unit_tests_dbms`, 例如：
```
# 默认运行所有的单元测试
./unit_tests_dbms 
```

运行某个模块的单元测试, 使用`--gtest_filter` + 模块名：
```
root@ubantu64:~/work/ClickHouse/build/src# ./unit_tests_dbms  --gtest_filter="T64Test.*"
Note: Google Test filter = T64Test.*
[==========] Running 1 test from 1 test suite.
[----------] Global test environment set-up.
[----------] 1 test from T64Test
[ RUN      ] T64Test.TranscodeRawInput
[       OK ] T64Test.TranscodeRawInput (49 ms)
[----------] 1 test from T64Test (49 ms total)

[----------] Global test environment tear-down
[==========] 1 test from 1 test suite ran. (54 ms total)
[  PASSED  ] 1 test.
```
