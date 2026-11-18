file="$(items_dir)/${args[target]}"
[[ -f "${file}" ]] || { echo "Error: no such item: ${args[target]}" >&2; exit 1; }
if [[ -n "${args[--dry-run]:-}" ]]; then
  echo "would remove ${args[target]}"
  exit 0
fi
[[ -n "${args[--force]:-}" ]] || { echo "Error: refusing to remove ${args[target]} without --force" >&2; exit 1; }
rm "${file}"
echo "removed ${args[target]}"
