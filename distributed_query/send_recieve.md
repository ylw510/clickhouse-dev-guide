## 数据接收端
负责分布式查询执行的节点来接收其他分片的数据.

使用RemoteSource来接收数据：
```
RemoteSource::tryGenerate()  ->
  RemoteQueryExecutor::readAsync()  ->
    RemoteQueryExecutor::processPacket(Packet packet)
```
一般一个分布式查询会涉及 4 种类型的packet：
（1）Protocol::Server::Data，数据包

（2）Protocol::Server::Progress，记录读取进度统计信息的包

（3）Protocol::Server::ProfileEvents，记录一些远端服务器性能事件的包

（4）Protocol::Server::EndOfStream，表示对端数据已经没有了

传输的数据格式表现为一个Block.

## 数据发送端
```
TCPHandler::sendData(QueryState & state, const Block & block)
```
