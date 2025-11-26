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
