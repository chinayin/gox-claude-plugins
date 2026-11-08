# 只接受字面量参数和 cd ... && git push；不执行 shell，不展开变量、替换或通配符。
# 单引号保留原文；双引号只接受无展开、无转义的文本。复杂命令由调用者拒绝。
def part:
  "'[^'\\r\\n\\t]*'|\"[^\"$`\\\\\\r\\n\\t]*\"|[^\\s'\"\\\\$`;&|<>(){}\\[\\]~*?#]+";

. as $command
| if test("[\\r\\n]") then error("multiline command") else . end
| [scan("(?:" + part + ")+|&&|[ \\t]+")]
| if join("") != $command then error("non-literal shell syntax") else . end
| map(select(test("^[ \\t]+$") | not))
| map(if . == "&&" then . else
    [scan(part) | if startswith("'") or startswith("\"") then .[1:-1] else . end] | join("")
  end)
