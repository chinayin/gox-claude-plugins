给这个 CLI 加一个 status 子命令：输出条目总数，支持 --json。另外给 scripts/release.sh 加一个 --dry-run 选项，带上它时只打印将要写入的版本号，不改 VERSION 文件。
