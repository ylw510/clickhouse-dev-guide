
### 创建一个虚拟环境
在`/root/work/ClickHouse/tests/integration`创建一个虚拟环境：
```
python3 -m venv integration-venv
```
查看创建的产物：
```
find . -type d -name "venv" -o -name ".venv" 2>/dev/null
```
激活虚拟环境：
```
source venv/bin/activate
```
### 前置条件

- Ubuntu 20.04 (Focal) 或更高版本

- Docker（API 版本 ≥ 1.25；使用 docker version 检查）

- 从官方文档安装最新版 Docker。不要使用系统仓库中的 Docker
- 安装 pip 和 libpq-dev：
```
sudo apt-get install python3-pip libpq-dev zlib1g-dev libcrypto++-dev libssl-dev libkrb5-dev python3-dev openjdk-17-jdk requests urllib3
```
- pytest 测试框架：
```
sudo -H pip install pytest
```
- docker compose 和其他 Python 库：
```
sudo -H pip install \
    PyMySQL avro cassandra-driver confluent-kafka dicttoxml docker grpcio grpcio-tools kafka-python kazoo minio \
    lz4 protobuf psycopg2-binary pymongo pytz pytest pytest-timeout redis tzlocal==2.1 urllib3 requests-kerberos dict2xml \
    hypothesis pika nats-py pandas numpy jinja2 pytest-xdist==2.4.0 pyspark azure-storage-blob delta paramiko psycopg pyarrow boto3 deltalake snappy pyiceberg python-snappy thrift
```
可以使用清华的镜像下载：
```
# 使用清华镜像源
sudo pip install \
    PyMySQL avro cassandra-driver confluent-kafka dicttoxml docker grpcio grpcio-tools kafka-python kazoo minio lz4 protobuf psycopg2-binary pymongo pytz pytest pytest-timeout redis tzlocal==2.1 urllib3 requests-kerberos dict2xml hypothesis pika nats-py pandas numpy jinja2 pytest-xdist==2.4.0 pyspark azure-storage-blob delta paramiko psycopg pyarrow boto3 deltalake snappy pyiceberg python-snappy thrift \
    -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --timeout=300
```
期间可能会缺少的包：
```
# 安装 krb5 开发包
sudo apt-get install libkrb5-dev krb5-config -y
```
使用`pip list`查看当前虚拟环境中已经安装的包：
```
pip list
```
- 对于 Spark 测试： 安装 Spark 并将其 bin 目录添加到 PATH 环境变量。详见 ci/docker/integration/runner/Dockerfile。设置 JAVA_PATH 为 Java 二进制文件路径。

- 以非特权用户运行测试： 将用户添加到 docker 组：
```
sudo usermod -aG docker $USER
# 重新登录或重启计算机
```

### 运行测试
使用 pytest 运行测试。示例和常用参数：
```
pytest <测试或路径> \
  [-k <表达式>] \
  [-n <进程数> --dist=loadfile] \
  [--count <次数> --repeat-scope=function]
```
参数说明：

-n <进程数>：并行进程数（CI 对可并行测试使用 4，其他测试使用 1）。并行运行时使用 --dist=loadfile 将同一文件的测试保持在同一工作进程。详见 pytest-xdist。

--count <次数>：重复测试多次；与 --repeat-scope=function 配合使用。详见 pytest-repeat。

测试在代码仓库根目录查找服务器二进制文件，在 `./programs/server/` 查找配置文件。可通过以下环境变量覆盖路径：
- CLICKHOUSE_TESTS_SERVER_BIN_PATH

- CLICKHOUSE_TESTS_ODBC_BRIDGE_BIN_PATH（clickhouse-odbc-bridge 二进制文件路径）

- CLICKHOUSE_TESTS_CLIENT_BIN_PATH

- CLICKHOUSE_TESTS_BASE_CONFIG_DIR（config.xml 和 users.xml 路径）
构建说明：
如果使用分离构建（ENABLE_CLICKHOUSE_ALL=OFF），需构建所有必需组件（例如 ENABLE_CLICKHOUSE_KEEPER=ON）。使用 ENABLE_CLICKHOUSE_ALL=ON 更简单。


### 网络慢无法使用docker拉镜像怎么办？
提前下载所有测试依赖的 Docker 镜像。
### 本地跑集成测试需要制作一个docker镜像
```
root@ubantu64:~/work/ClickHouse/docker/server# pwd
/root/work/ClickHouse/docker/server
root@ubantu64:~/work/ClickHouse/docker/server# docker build -t clickhouse/integration-test:latest -f Dockerfile.ubuntu .
```
```
root@ubantu64:~/work/ClickHouse/docker/server# docker images|grep inte
clickhouse/integration-test                                 latest    7153119c0a63   11 minutes ago   828MB
```
可能需要ubuntu:22.04:
```
docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/ubuntu:22.04
```
打tag成`DockerFile`中需要的名字：
```
docker tag swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/ubuntu:22.04 ubuntu:22.04
```

1️⃣ 清理残留容器
```
export PYTEST_CLEANUP_CONTAINERS=1
pytest --cleanup-containers
```
