## 如何生成函数的返回值类型
```
需要实现`getReturnTypeImpl`接口:
DataTypePtr IFunction::getReturnTypeImpl(const DataTypes & /*arguments*/) const
{
    throw Exception(ErrorCodes::NOT_IMPLEMENTED, "getReturnType is not implemented for {}", getName());
}
```
例如小于等于的实现`LessOrEqualsOp`,会在解析层的`resolveFunction`的`build`调用。
```
5. DB::FunctionComparison<DB::LessOrEqualsOp, DB::NameLessOrEquals>::getReturnTypeImpl(std::vector<std::shared_ptr<DB::IDataType const>, std::allocator<std::shared_ptr<DB::IDataType const>>> const&) const @ 0x000000000c899692
6. DB::IFunction::getReturnTypeImpl(std::vector<DB::ColumnWithTypeAndName, std::allocator<DB::ColumnWithTypeAndName>> const&) const @ 0x000000000908b0cc
7. DB::IFunctionOverloadResolver::getReturnType(std::vector<DB::ColumnWithTypeAndName, std::allocator<DB::ColumnWithTypeAndName>> const&) const @ 0x0000000013ba27f1
8. DB::IFunctionOverloadResolver::build(std::vector<DB::ColumnWithTypeAndName, std::allocator<DB::ColumnWithTypeAndName>> const&) const @ 0x0000000013ba2dc1
9. DB::QueryAnalyzer::resolveFunction(std::shared_ptr<DB::IQueryTreeNode>&, DB::IdentifierResolveScope&) @ 0x000000001539009b
10. DB::QueryAnalyzer::resolveExpressionNode(std::shared_ptr<DB::IQueryTreeNode>&, DB::IdentifierResolveScope&, bool, bool, bool) @ 0x000000001513404a
11. DB::QueryAnalyzer::resolveExpressionNodeList(std::shared_ptr<DB::IQueryTreeNode>&, DB::IdentifierResolveScope&, bool, bool) @ 0x000000001513360e
```
`resolveFunction`用来解析一个函数。
