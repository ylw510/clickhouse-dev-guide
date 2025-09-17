### Broken Part产生原因
当重启Server或者restart 表时，会加载Part，之后CK会对Part进行安全检查，如果通过了安全检查才会将它视为正常Part。
没有通过安全检查的part会将它添加到`unexpected_data_parts`中。

#### 添加unexpected_data_parts流程
总入口函数在`MergeTreeData::loadDataParts`,

从磁盘加载part到内存，注意只是元信息的加载：
MergeTreeData::loadDataPart
loadDataPart主要加载两部分的元信息

- MergeTreeDataPartBuilder::build()，基础信息的构建，例如根据part_type构建这个part时Compart格式还是Wide格式
- 通过 `IMergeTreeDataPart::loadColumnsChecksumsIndexes` 来加载列信息，index信息，checksum等等
如果之前有些异常操作（例如直接关机，此时就会产生破损part[这里主要是应该ck为了写入性能，默认不是`fsync`写磁盘]，通过[https://clickhouse.com/docs/operations/settings/merge-tree-settings#fsync_after_insert]开启）。
之后服务重启加载表的Part时，就会很容易在上述第二步检测到破损Part。

如果加载的过程出现异常，便会将本次加载结果的`is_broken`设置为`true`:
```
    /// Ignore broken parts that can appear as a result of hard server restart.
    auto mark_broken = [&]
    {
        if (!res.part)
        {
            /// Build a fake part and mark it as broken in case of filesystem error.
            /// If the error impacts part directory instead of single files,
            /// an exception will be thrown during detach and silently ignored.
            res.part = getDataPartBuilder(part_name, single_disk_volume, part_name, getReadSettings())
                .withPartStorageType(MergeTreeDataPartStorageType::Full)
                .withPartType(MergeTreeDataPartType::Wide)
                .build();
        }

        res.is_broken = true;
        tryLogCurrentException(log, fmt::format("while loading part {} on path {}", part_name, part_path));

        res.size_of_part = calculatePartSizeSafe(res.part, log.load());
        auto part_size_str = res.size_of_part ? formatReadableSizeWithBinarySuffix(*res.size_of_part) : "failed to calculate size";

        LOG_ERROR(log,
            "Detaching broken part {} (size: {}). "
            "If it happened after update, it is likely because of backward incompatibility. "
            "You need to resolve this manually",
            fs::path(getFullPathOnDisk(part_disk_ptr)) / part_name, part_size_str);
    };
```

对于一个复制表：

(1) 首先从keeper的表副本路径上拉取parts znode下的所有part，这个part只是part的元信息，不包含数据.之后将所有的part名添加到`expected_parts_on_this_replica`中：
```
std::optional<std::unordered_set<std::string>> expected_parts_on_this_replica;
```
Keeper中的parts路径下添加part，产生的时机为：
- 向表中写入数据，之后提交part到Keeper
- 合并后的part提交到keeper

(2) 之后在loadDataParts中会比较当前节点磁盘中所有的物理part，如果part不在`expected_parts_on_this_replica`中，则将它添加到`unexpected_disk_parts`中。对于正常存在的添加到`parts_to_load_by_disk`中：
```
    std::vector<PartLoadingTree::PartLoadingInfos> parts_to_load_by_disk(disks.size());
    std::vector<PartLoadingTree::PartLoadingInfos> unexpected_parts_to_load_by_disk(disks.size());

    ThreadPoolCallbackRunnerLocal<void> runner(getActivePartsLoadingThreadPool().get(), "ActiveParts");

    bool all_disks_are_readonly = true;
    for (size_t i = 0; i < disks.size(); ++i)
    {
        const auto & disk_ptr = disks[i];
        if (disk_ptr->isBroken())
            continue;
        if (!disk_ptr->isReadOnly())
            all_disks_are_readonly = false;

        auto & disk_parts = parts_to_load_by_disk[i];
        auto & unexpected_disk_parts = unexpected_parts_to_load_by_disk[i];

        runner([&expected_parts, &unexpected_disk_parts, &disk_parts, this, disk_ptr]()
        {
            for (auto it = disk_ptr->iterateDirectory(relative_data_path); it->isValid(); it->next())
            {
                /// Skip temporary directories, file 'format_version.txt' and directory 'detached'.
                if (startsWith(it->name(), "tmp")
                    || it->name() == MergeTreeData::FORMAT_VERSION_FILE_NAME
                    || it->name() == DETACHED_DIR_NAME)
                    continue;

                if (auto part_info = MergeTreePartInfo::tryParsePartName(it->name(), format_version))
                {
                    if (expected_parts && !expected_parts->contains(it->name()))
                        unexpected_disk_parts.emplace_back(*part_info, it->name(), disk_ptr);
                    else
                        disk_parts.emplace_back(*part_info, it->name(), disk_ptr);
                }
            }
        }, Priority{0});
    }
```
#### 本地part在keeper的parts
(3) 对于`parts_to_load_by_disk`存放的part是需要加载到内存中的。

  - 第一步需要构建一个加载树，通过`PartLoadingTree::build`完成。
    因为这些 part 之间可能是包含关系（例如一个 part 是另一些小 part 合并出来的），所以需要建立一棵“包含关系”的树，来决定加载的先后顺序。此结构使得当某个 part 损坏时，可以加载它的子 part（被它覆盖的原始数据），从而“修复”数据。

    每个 part 有如下属性：
    - partition_id
    - min_block, max_block
    - level
    
    多个 part 在同一个分区中有如下关系：
    ```
           A (covering part)
          / \
         B   C   (smaller parts)
    ```
    PartLoadingTree 就是建这样一棵树：
    - A 是 root
    - B/C 是 A 的 children
    - 如果 A 损坏，就会加载 B 和 C 来替代
   
(4) 通过`traverse`将树中顶层part加入到`active_parts`中
```
    PartLoadingTreeNodes active_parts;

    /// Collect only "the most covering" parts from the top level of the tree.
    loading_tree.traverse(/*recursive=*/ false, [&](const auto & node)
    {
        active_parts.emplace_back(node);
    });
```
(5) 通过`loadDataPartsFromDisk`磁盘中加载`active_parts`。之后遍历加载的结果`loaded_parts`，如果加载part的表示`is_broken`为true，并且它不在从keeper上拿到的parts中。
    则统计broken part，以及broken part的字节数：
    ```
        if (res.is_broken)
    {
        broken_parts_to_detach.push_back(res.part);
        bool unexpected = expected_parts != std::nullopt && !expected_parts->contains(res.part->name);
        if (unexpected)
        {
            LOG_DEBUG(log, "loadDataParts: Part {} is broken, but it's not expected to be in parts set, "
                      " will not count it as suspicious broken part", res.part->name);
            ++suspicious_broken_unexpected_parts;
        }
        else
            ++suspicious_broken_parts;

        if (res.size_of_part)
        {
            if (unexpected)
                suspicious_broken_unexpected_parts_bytes += *res.size_of_part;
            else
                suspicious_broken_parts_bytes += *res.size_of_part;
        }
    }
    ```

(6) 如果破损的part数大于mergetree setting：`max_suspicious_broken_parts`，或者破损part的字节数大于：`max_suspicious_broken_parts_bytes`。则加载part失败，进而导致server启动失败。
```
if (!skip_sanity_checks)
{
    if (suspicious_broken_parts > (*settings)[MergeTreeSetting::max_suspicious_broken_parts])
        throw Exception(
            ErrorCodes::TOO_MANY_UNEXPECTED_DATA_PARTS,
            "Suspiciously many ({} parts, {} in total) broken parts "
            "to remove while maximum allowed broken parts count is {}. You can change the maximum value "
            "with merge tree setting 'max_suspicious_broken_parts' in <merge_tree> configuration section or in table settings in .sql file "
            "(don't forget to return setting back to default value)",
            suspicious_broken_parts,
            formatReadableSizeWithBinarySuffix(suspicious_broken_parts_bytes),
            (*settings)[MergeTreeSetting::max_suspicious_broken_parts].value);

    if (suspicious_broken_parts_bytes > (*settings)[MergeTreeSetting::max_suspicious_broken_parts_bytes])
        throw Exception(
            ErrorCodes::TOO_MANY_UNEXPECTED_DATA_PARTS,
            "Suspiciously big size ({} parts, {} in total) of all broken "
            "parts to remove while maximum allowed broken parts size is {}. "
            "You can change the maximum value with merge tree setting 'max_suspicious_broken_parts_bytes' in <merge_tree> configuration "
            "section or in table settings in .sql file (don't forget to return setting back to default value)",
            suspicious_broken_parts,
            formatReadableSizeWithBinarySuffix(suspicious_broken_parts_bytes),
            formatReadableSizeWithBinarySuffix((*settings)[MergeTreeSetting::max_suspicious_broken_parts_bytes]));
}
```
(7) 如果该表所在的存储不是可读或者只写一次，则将第(5)步检测到的破损part重命名为：以"broken-on-start"为前缀再加分区名，则后移动到detached目录下。
Note：以上(3) - (7)之间都是对本地part在keeper的parts路径下part的处理流程。
(8) 对unexpected的part处理基本与excepted的part一致：
```
for (auto & load_state : unexpected_data_parts)
{
    std::lock_guard lock(unexpected_data_parts_mutex);
    chassert(!load_state.part);
    if (unexpected_data_parts_loading_canceled)
    {
        runner.waitForAllToFinishAndRethrowFirstError();
        return;
    }
    runner([&]()
    {
        loadUnexpectedDataPart(load_state);

        chassert(load_state.part);
        if (load_state.is_broken)
            load_state.part->renameToDetached("broken-on-start", /*ignore_error=*/ replicated); /// detached parts must not have '_' in prefixes
    }, Priority{});
}
```
(9) 对于已经覆盖了的part：
```
loading_tree.traverse(/*recursive=*/ true, [&](const auto & node)
{
    if (!node->is_loaded)
        unloaded_parts.push_back(node);
});

/// By the way, if all disks are readonly, it does not make sense to load outdated parts (we will not own them).
if (!unloaded_parts.empty() && !all_disks_are_readonly)
{
    LOG_DEBUG(log, "Found {} outdated data parts. They will be loaded asynchronously", unloaded_parts.size());

    {
        std::lock_guard lock(outdated_data_parts_mutex);
        outdated_unloaded_data_parts = std::move(unloaded_parts);
        outdated_data_parts_loading_finished = false;
    }

    outdated_data_parts_loading_task = getContext()->getSchedulePool().createTask(
        "MergeTreeData::loadOutdatedDataParts",
        [this] { loadOutdatedDataParts(/*is_async=*/ true); });
}
```
#### 本地part不在keeper的parts
对于本地part不在keeper的parts路径中的处理是在ReplicatedMergeTreeAttachThread::runImpl中完成的
```
ReplicatedMergeTreeAttachThread::runImpl()  ->
  StorageReplicatedMergeTree::checkParts()  ->
    StorageReplicatedMergeTree::checkPartsImpl()
```
