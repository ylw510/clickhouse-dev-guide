## 相关文件
Disks/IVolume.h：抽象出来的磁盘逻辑卷，其中包含了Disk，以及磁盘选择算法ROUND_ROBIN（轮询），LEAST_USED（最少使用）。

Disks/VolumeJBOD.h：实现了 JBOD (Just a Bunch Of Disks) 模式，
- 多个磁盘组成一个卷，但不做 RAID，也不做数据复制。

- 当写入新数据 part 时，会按照负载均衡策略选择一个磁盘去存储。


Disks/registerDisks.cpp:注册所有类型的磁盘。

Disks/ObjectStorages/RegisterDiskObjectStorage.h：包含注册类型为对象存储的磁盘.其中包含了creator。

Disks/DiskLocal.cpp: 注册本地磁盘

Disks/ObjectStorages/ObjectStorageFactory.cpp：创建对象存储类型磁盘的工厂类。

Disks/ObjectStorages/S3/S3ObjectStorage.h: 对S3对象存储的抽象。

Disks/DiskSelector.cpp：磁盘选择器。包含所有已经创建的磁盘。

Disks/ObjectStorages/MetadataStorageFactory.cpp：元信息存储创建工厂类。

Disks/DiskFactory.cpp: 创建磁盘工厂类。对于对象存储的磁盘，它需要对象存储以及元信息存储。


disk0：MetadataStorageFromPlainObjectStorageTransaction

disk1：MetadataStorageFromDiskTransaction

disk0: MetadataStorageFromPlainObjectStorage

disk1: MetadataStorageFromDisk
