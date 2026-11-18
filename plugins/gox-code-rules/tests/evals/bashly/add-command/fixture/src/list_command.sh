limit="${args[--limit]:-0}"
if [[ -n "${args[--json]:-}" ]]; then
  items_list "$(items_dir)" "${limit}" | items_to_json
else
  items_list "$(items_dir)" "${limit}"
fi
