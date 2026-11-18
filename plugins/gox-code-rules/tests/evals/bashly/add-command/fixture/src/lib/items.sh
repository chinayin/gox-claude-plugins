# 条目存放在 ITEMS_DIR（默认 ./items）下，每个文件一条
items_dir() {
  echo "${ITEMS_DIR:-./items}"
}

items_list() {
  local dir="${1}" limit="${2:-0}" count=0 f
  [[ -d "${dir}" ]] || return 0
  for f in "${dir}"/*; do
    [[ -f "${f}" ]] || continue
    basename "${f}"
    count=$((count + 1))
    if [[ "${limit}" -gt 0 && "${count}" -ge "${limit}" ]]; then break; fi
  done
}

items_to_json() {
  jq -R . | jq -sc .
}
