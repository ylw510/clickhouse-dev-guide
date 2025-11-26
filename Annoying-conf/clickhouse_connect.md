### python 3.9安装
clickhouse_connect 需要python3.9.
将Deadsnakes PPA添加到系统的来源列表中：
- sudo add-apt-repository ppa:deadsnakes/ppa
- sudo apt install python3.9


### 对应虚拟环境组件
sudo apt install python3.9-venv.

不装这个会报错：
```
root@ubantu24:~# python3.9 -m venv ~/clickhouse_env
Error: Command '['/root/clickhouse_env/bin/python3.9', '-m', 'ensurepip', '--upgrade', '--default-pip']' returned non-zero exit status 1.
```

### 虚拟环境
1.创建虚拟环境但不安装 pip
python3.9 -m venv ~/clickhouse_env

2.激活虚拟环境
source ~/clickhouse_env/bin/activate

### 示例连接代码
这段代码目前有性能问题，应该python有个全局锁对计算密集型的线程不利。
```
import time
import datetime
import random
import json
import threading
from queue import Queue, Empty
from clickhouse_connect import get_client

# =====================================
# 配置
# =====================================
ROWS_PER_BATCH = 100_000     # 每次 Producer 产生的数据规模
PRODUCER_COUNT = 4           # 生产线程数量
SENDER_COUNT = 4             # 发送线程数量
RUN_SECONDS = 3600           # 默认运行时间
QUEUE_SIZE = 100              # 队列背压，防止 OOM
TABLE = "default.test"

batch_queue = Queue(maxsize=QUEUE_SIZE)
stop_event = threading.Event()

# 全局 version 控制
version_lock = threading.Lock()
current_version = 1

# 全局统计
stats_lock = threading.Lock()
total_produced = 0
total_inserted = 0

# =====================================
# 随机 JSON 数据生成
# =====================================
def random_json():
    return json.dumps({
        "name": f"server-{random.randint(1, 999999)}",
        "ip": f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}",
        "cpu": random.choice([2,4,8,16,32,64]),
        "mem": random.choice([2048,4096,8192,16384,32768,65536]),
        "owner": f"user_{random.randint(1,5000)}",
        "time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    })

# =====================================
# Producer 线程
# =====================================
def producer_thread(thread_id):
    global current_version, total_produced
    print(f"[Producer-{thread_id}] started")

    while not stop_event.is_set():
        start_time = time.time()
        with version_lock:
            old_ver = current_version
            new_ver = current_version + 1
            current_version = new_ver

        now = datetime.datetime.now()
        batch = []
        for _ in range(ROWS_PER_BATCH):
            instance_id = random.randint(0, 999_999)
            v = random_json()
            batch.append((instance_id, "cmdb", 1, "{}", None, None, -1, old_ver))
            batch.append((instance_id, "cmdb", 1, v, now, now, 1, new_ver))

        batch_queue.put(batch)  # 阻塞队列实现背压

        batch_time = time.time() - start_time
        with stats_lock:
            total_produced += len(batch)

        print(f"[Producer-{thread_id}] produced {len(batch)} rows (ver {old_ver}->{new_ver}) "
              f"in {batch_time:.2f}s | Queue size: {batch_queue.qsize()}")

    print(f"[Producer-{thread_id}] stopped")

# =====================================
# Sender 线程，每个线程独立 Client
# =====================================
def sender_thread(sender_id):
    global total_inserted
    local_client = get_client(
        host='10.241.180.5',
        port=9701,
        username='default',
        password='!@bonreeclickhouse'
    )
    print(f"[Sender-{sender_id}] started")

    while not (stop_event.is_set() and batch_queue.empty()):
        try:
            batch = batch_queue.get(timeout=1)
        except Empty:
            continue

        start_time = time.time()
        local_client.insert(
            TABLE, batch,
            column_names=["instance_id","model_key","e_id","v","t","insert_time","sign","version"]
        )
        batch_time = time.time() - start_time

        with stats_lock:
            total_inserted += len(batch)

        print(f"[Sender-{sender_id}] inserted {len(batch)} rows in {batch_time:.2f}s | Queue size: {batch_queue.qsize()}")
        batch_queue.task_done()

    print(f"[Sender-{sender_id}] stopped")

# =====================================
# 初始化 ClickHouse
# =====================================
def init_clickhouse():
    client = get_client(
        host='10.241.180.5',
        port=9701,
        username='default',
        password='!@bonreeclickhouse'
    )
    client.command(f"DROP TABLE IF EXISTS {TABLE}")
    client.command(f"""
    CREATE TABLE {TABLE}
    (
        instance_id Int64,
        m_string String,
        e_id UInt16,
        v JSON,
        t Nullable(DateTime('Asia/Shanghai')),
        insert_time Nullable(DateTime('Asia/Shanghai')),
        sign Int8,
        version UInt64
    )
    ENGINE = VersionedCollapsingMergeTree(sign, version)
    PARTITION BY toUInt8(instance_id % 100)
    ORDER BY (instance_id, e_id, model_key)
    """)

# =====================================
# 主程序
# =====================================
if __name__ == "__main__":
    init_clickhouse()

    # 启动 Sender 线程
    senders = []
    for i in range(SENDER_COUNT):
        t = threading.Thread(target=sender_thread, args=(i,), daemon=True)
        t.start()
        senders.append(t)

    # 启动 Producer 线程
    producers = []
    for i in range(PRODUCER_COUNT):
        t = threading.Thread(target=producer_thread, args=(i,), daemon=True)
        t.start()
        producers.append(t)

    print("=== Running multi-producer / multi-sender pipeline ===")

    try:
        start_time = time.time()
        while time.time() - start_time < RUN_SECONDS:
            time.sleep(60)
            # 每秒打印总统计信息
            with stats_lock:
                elapsed = time.time() - start_time
                print(f"[Stats] Elapsed: {int(elapsed)}s | Total produced: {total_produced} | Total inserted: {total_inserted} | Queue size: {batch_queue.qsize()}")
    except KeyboardInterrupt:
        print("\n=== Ctrl+C detected, stopping pipeline ===")
    finally:
        stop_event.set()
        # 等待队列处理完成
        batch_queue.join()
        # 等待 Sender 线程退出
        for t in senders:
            t.join()
        print(f"=== Pipeline stopped gracefully | Total produced: {total_produced} | Total inserted: {total_inserted} ===")
```
