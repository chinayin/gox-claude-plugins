# 只接受字面量参数和 cd ... && git push；不执行 shell，不展开变量、替换或通配符。
# 单引号保留原文；双引号只接受无展开、无转义的文本。复杂命令由调用者拒绝。
def part:
  "'[^'\\r\\n\\t]*'|\"[^\"$`\\\\\\r\\n\\t]*\"|[^\\s'\"\\\\$`;&|<>(){}\\[\\]~*?#]+";

def literal_args:
  . as $command
  | if test("[\\r\\n]") then error("multiline command") else . end
  | [scan("(?:" + part + ")+|&&|[ \\t]+")]
  | if join("") != $command then error("non-literal shell syntax") else . end
  | map(select(test("^[ \\t]+$") | not))
  | map(if . == "&&" then . else
      [scan(part) | if startswith("'") or startswith("\"") then .[1:-1] else . end] | join("")
    end);

# 只证明少量完整命令的参数是文本；未知程序、执行型选项及 shell 展开不放行。
# 此模式不放宽下面默认使用的范围解析器。
def text_arguments:
  try (
    literal_args as $words
    | if ($words | index("&&")) != null then false
      elif (["echo", "cat", "grep"] | index($words[0])) != null then true
      elif $words[0] == "printf" then
        # -v / %n 的变量名可触发下标求值；只确认普通文字、固定宽度 %s 和 %%。
        (($words[1] // "") | startswith("-v") | not)
        and ((if $words[1] == "--" then $words[2] else $words[1] end) // ""
          | gsub("%%|%[-0-9.]*s"; "") | contains("%") | not)
      elif $words[0] == "rg" then
        any($words[1:][]; . == "--pre" or startswith("--pre=")
          or . == "--hostname-bin" or startswith("--hostname-bin=")) | not
      else false end
  ) catch false;

# 只接受单个 cat 的引用 heredoc；首个结束标记后不能再有命令。
# 引用 delimiter 时，正文里的 $() / 反引号均为字面量，不会执行。
def quoted_cat_heredoc:
  (try (
    sub("\n$"; "") | split("\n") as $lines
    | ($lines[0] | capture("^[ \\t]*cat[ \\t]+<<(?<strip>-?)[ \\t]*(?<quote>['\"])(?<end>[A-Za-z_][A-Za-z_0-9]*)\\k<quote>[ \\t]*$")) as $header
    | ($lines[1:] | map(if $header.strip == "-" then sub("^\t*"; "") else . end)) as $body
    | ($body | index($header.end)) as $end
    | $end != null and $end == ($body | length) - 1
  ) catch false) // false;

if ($ARGS.named.mode // "") == "text" then
  text_arguments or quoted_cat_heredoc
else
  literal_args
end
