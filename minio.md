## 如何安装
```
# 建议root操作
wget http://dl.minio.org.cn/server/minio/release/linux-amd64/minio
chmod +x minio

# 启动
./minio server /data

# 可以移动到/usr/bin
mv minio /usr/bin/
```
检查版本
```
root@ubantu64:~# minio --version
minio version RELEASE.2025-07-23T15-54-02Z (commit-id=7ced9663e6a791fef9dc6be798ff24cda9c730ac)
Runtime: go1.24.5 linux/amd64
License: GNU AGPLv3 - https://www.gnu.org/licenses/agpl-3.0.html
Copyright: 2015-2025 MinIO, Inc.
```
