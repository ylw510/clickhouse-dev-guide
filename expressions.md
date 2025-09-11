## 如何构造语法树

例如构造一个表达式列表的语法树：
```
ASTPtr default_expr_list = std::make_shared<ASTExpressionList>();
```
如何构造一个函数的语法树？
使用：`makeASTFunction`，其定义如下：
```
template <typename... Args>
std::shared_ptr<ASTFunction> makeASTFunction(const String & name, Args &&... args)
{
    auto function = std::make_shared<ASTFunction>();

    function->name = name;
    function->arguments = std::make_shared<ASTExpressionList>();
    function->children.push_back(function->arguments);

    function->arguments->children = { std::forward<Args>(args)... };

    return function;
}
```

例如构造cast函数的语法树，其中`column_default_expr`和`required_type`为cast函数的参数
```
auto required_type = std::make_shared<ASTLiteral>(object_columns.get(required_column_name).type->getName());
ASTPtr column_default_expr = std::make_shared<ASTLiteral>(default_value);
auto expr = makeASTFunction("_CAST", column_default_expr, required_type);
```
将创建好的cast函数语法树添加到表达式列表`default_expr_list`:
```
# setAlias 用来设置表达式的别名，要想使用这个函数，需要语法树继承ASTWithAlias
default_expr_list_accum->children.emplace_back(setAlias(expr, required_column_name));
```

## 如何将语法树转化为表达式
使用`createExpressions`:
```
std::optional<ActionsDAG> createExpressions(
    const Block & header,
    ASTPtr expr_list,
    bool save_unneeded_columns,
    ContextPtr context)
{
    if (!expr_list)
        return {};

    auto syntax_result = TreeRewriter(context).analyze(expr_list, header.getNamesAndTypesList());
    auto expression_analyzer = ExpressionAnalyzer{expr_list, syntax_result, context};
    ActionsDAG dag(header.getNamesAndTypesList());
    auto actions = expression_analyzer.getActionsDAG(true, !save_unneeded_columns);
    return ActionsDAG::merge(std::move(dag), std::move(actions));
}
```
header：`header`为这个表达式输出列以及结果类型，例如 `select c1+ c2, c3`子句中的`c1+ c2, c3`就是`header`中的两个列。它们会作为`ActionsDAG`的输入
expr_list：`expr_list`为刚才创建的表达式列表。

如何构造一个可执行的表达式：
```
# 将createExpressions生成的ActionsDag作为参数传给ExpressionActions，ExpressionActions是可执行的表达式
auto actions = std::make_shared<ExpressionActions>(
    std::move(*dag),
    ExpressionActionsSettings(data_part_info_for_read->getContext()->getSettingsRef()));

actions->execute(additional_columns);
```
示例中,`additional_columns`为一个`Block`，它里面存的是数据，而后的表达式计算也是基于这个Block中的输入进行的。

