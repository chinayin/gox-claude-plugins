file="$(items_dir)/${args[target]}"
[[ -f "${file}" ]] || { echo "Error: no such item: ${args[target]}" >&2; exit 1; }
if [[ -n "${args[--json]:-}" ]]; then
  jq -n --arg name "${args[target]}" --rawfile body "${file}" '{name: $name, body: $body}'
else
  cat "${file}"
fi
