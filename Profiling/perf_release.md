## BG
生产环境中有些查询慢，但是无法通过看代码直接分析出来。这时候就需要使用一些性能分析工具，例如`perf`等。
但是perf的使用需要有符号表，而release一般是不带符号表的。

## perf联动符号表
使用以下命令将编译好的二进制程序中的debug节脱离出来。
```
objcopy --only-keep-debug yourBinary yourBinary.debug
```
再使用`--add-gnu-debuglink`将debug信息与二进制文件关联起来。同时二进制程序也不会臃肿，只是会多了一个debug link的节。
```
objcopy --add-gnu-debuglink=yourBinary.debug yourBinary
```
经过以上操作后，使用Perf分析不带符号表的二进制程序时，就能看出热点函数名了，而不再是unknow了。
