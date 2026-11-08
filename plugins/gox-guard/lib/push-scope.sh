#!/usr/bin/env bash
# 供 secrets hook source：只读解析仓库与提交范围，失败返回非零，由 hook 输出拒绝。
# 与 hook 相同，仅 set -u；不在此处输出协议或执行用户命令。
set -u

# 设置 REPO、RANGE 数组和失败原因 SCOPE_ERROR，供 secrets.sh 读取。
# RANGE 只含 Git 解析出的提交 ID 或固定的 revision 选项。
# shellcheck disable=SC2034
resolve_push_scope() {
  local command="$1" cwd="$2" tokens token directory default_override=""
  local remote="" branch configured mode source oid names ref options=1 delete=0
  local all=0 tags=0 mirror=0 recurse=""
  local -a words sources
  words=() sources=() RANGE=() SCOPE_ERROR=""
  tokens="$(printf '%s' "$command" | jq -Rsc -f "$GUARD_LIB_DIR/literal-args.jq" 2>/dev/null)" || return 1
  while IFS= read -r token; do words[${#words[@]}]="$token"; done <<<"$(jq -r '.[]' <<<"$tokens")"
  set -- "${words[@]}"
  cwd="$(CDPATH='' cd -- "$cwd" 2>/dev/null && pwd -P)" || return 1

  if [ "${1:-}" = cd ]; then
    shift
    case "${1:-}" in --) shift ;; -*) return 1 ;; esac
    [ "$#" -ge 3 ] && [ "$2" = '&&' ] && [ -n "$1" ] && [ "$1" != - ] || return 1
    cwd="$(CDPATH='' cd -- "$cwd" && CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)" || return 1
    shift 2
  fi
  # 先检查剩余所有 token，避免 tag / 选项值消费掉控制操作符。
  for token in "$@"; do [ "$token" != '&&' ] || return 1; done
  [ "${1:-}" = git ] || return 1
  shift
  while [ "$#" -gt 0 ] && [ "$1" != push ]; do
    case "$1" in
      -C) [ "$#" -ge 2 ] || return 1; directory="$2"; shift 2 ;;
      -C?*) directory="${1#-C}"; shift ;;
      -c)
        [ "$#" -ge 2 ] || return 1
        # 其余 -c 可能改变仓库、引用或子模块行为，无法保证扫描与 push 一致。
        case "$2" in push.default=*) default_override="${2#push.default=}" ;; *) return 1 ;; esac
        shift 2; continue ;;
      --no-pager|--no-optional-locks) shift; continue ;;
      *) return 1 ;;
    esac
    if [ -n "$directory" ]; then
      cwd="$(CDPATH='' cd -- "$cwd" && CDPATH='' cd -- "$directory" 2>/dev/null && pwd -P)" || return 1
    fi
  done
  [ "${1:-}" = push ] || return 1
  shift
  REPO="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || return 1

  while [ "$#" -gt 0 ]; do
    token="$1"; shift
    [ "$token" != '&&' ] || return 1
    if [ "$options" -eq 1 ]; then
      case "$token" in
        --) options=0; continue ;;
        --all|--branches) all=1; continue ;;
        --tags) tags=1; continue ;;
        --mirror) mirror=1; continue ;;
        -d|--delete) delete=1; continue ;;
        --recurse-submodules=no|--no-recurse-submodules) recurse=no; continue ;;
        --recurse-submodules=check) recurse=check; continue ;;
        -o|--push-option) [ "$#" -gt 0 ] || return 1; shift; continue ;;
        --push-option=*) continue ;;
        -u|-f|-n|-v|-q|--set-upstream|--force|--dry-run|--verbose|--quiet|--porcelain|--atomic|--prune|--progress|--thin|--no-thin|--verify|--no-verify|--follow-tags|--no-follow-tags|--signed|--no-signed|--signed=*|--force-with-lease|--force-with-lease=*|--force-if-includes|--no-force-if-includes) continue ;;
        -*) return 1 ;;
      esac
    fi
    if [ -z "$remote" ]; then remote="$token"; continue; fi
    if [ "$token" = tag ] && [ "$delete" -eq 0 ]; then
      [ "$#" -gt 0 ] || return 1
      token="refs/tags/$1"; shift
    fi
    sources[${#sources[@]}]="$token"
  done
  # 扫描器只看一个仓库，不能默许配置触发另一个仓库的 push。
  [ -n "$recurse" ] || recurse="$(git -C "$REPO" config --get push.recurseSubmodules 2>/dev/null || true)"
  if [ -z "$recurse" ] && [ "$(git -C "$REPO" config --bool --get submodule.recurse 2>/dev/null)" = true ]; then recurse=on-demand; fi
  case "$recurse" in
    ''|no|check) ;;
    *) SCOPE_ERROR='recursive submodule pushes require separate scans. Push each submodule separately, then run git push --recurse-submodules=no for the parent repository.'; return 1 ;;
  esac
  [ "$delete" -eq 0 ] || return 0

  # 与 Git 的 push 目标优先级一致；读取配置不连接远端。
  branch="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -z "$remote" ] && [ -n "$branch" ]; then remote="$(git -C "$REPO" config --get "branch.$branch.pushRemote" 2>/dev/null || true)"; fi
  [ -n "$remote" ] || remote="$(git -C "$REPO" config --get remote.pushDefault 2>/dev/null || true)"
  if [ -z "$remote" ] && [ -n "$branch" ]; then remote="$(git -C "$REPO" config --get "branch.$branch.remote" 2>/dev/null || true)"; fi
  if [ -z "$remote" ]; then
    configured="$(git -C "$REPO" remote 2>/dev/null)" || return 1
    case "$configured" in
      ''|*$'\n'*) remote=origin ;;
      *) remote="$configured" ;;
    esac
  fi
  # 远端组可能逐个采用不同 refspec；要求拆成单独的 push。
  [ -z "$(git -C "$REPO" config --get "remotes.$remote" 2>/dev/null)" ] || return 1
  if [ "$(git -C "$REPO" config --bool --get "remote.$remote.mirror" 2>/dev/null)" = true ]; then mirror=1; fi
  if [ "$mirror" -eq 1 ]; then RANGE=(--all); return 0; fi
  [ "$all" -eq 0 ] || RANGE[${#RANGE[@]}]=--branches
  [ "$tags" -eq 0 ] || RANGE[${#RANGE[@]}]=--tags

  if [ "${#sources[@]}" -eq 0 ] && [ "${#RANGE[@]}" -eq 0 ]; then
    configured="$(git -C "$REPO" config --get-all "remote.$remote.push" 2>/dev/null || true)"
    if [ -n "$configured" ]; then
      while IFS= read -r source; do sources[${#sources[@]}]="$source"; done <<<"$configured"
    else
      mode="${default_override:-$(git -C "$REPO" config --get push.default 2>/dev/null || true)}"
      case "$mode" in
        matching) RANGE=(--branches); return 0 ;;
        nothing) return 0 ;;
        ''|simple|current|upstream) sources=(HEAD) ;;
        *) return 1 ;;
      esac
    fi
  fi

  for source in ${sources[@]+"${sources[@]}"}; do
    source="${source#+}"
    # :/message 等 revision 表达式也能作为推送源，不能误判成纯删除。
    # 复杂的多冒号形式要求调用者先解析成显式提交 ID。
    case "$source" in *:*:*) return 1 ;; esac
    if [ "$source" = : ]; then RANGE[${#RANGE[@]}]=--branches; continue; fi
    source="${source%%:*}"
    [ -n "$source" ] || continue  # 删除 refspec 不发送提交。
    case "$source" in
      *'*'*)
        case "$source" in refs/*) ;; *) return 1 ;; esac
        names="$(git -C "$REPO" for-each-ref --format='%(refname)' 2>/dev/null)" || return 1
        while IFS= read -r ref; do
          # Git refspec 的 * 可以跨 /；这里匹配完整 ref，绝不交给 shell 展开文件名。
          # shellcheck disable=SC2254
          case "$ref" in $source) ;; *) continue ;; esac
          oid="$(git -C "$REPO" rev-parse --verify --end-of-options "$ref^{commit}" 2>/dev/null)" || return 1
          RANGE[${#RANGE[@]}]="$oid"
        done <<<"$names" ;;
      *)
        oid="$(git -C "$REPO" rev-parse --verify --end-of-options "$source^{commit}" 2>/dev/null)" || return 1
        RANGE[${#RANGE[@]}]="$oid" ;;
    esac
  done
}
