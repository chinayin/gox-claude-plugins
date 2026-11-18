用 bash 写一个部署管理的命令行工具 deployctl，有 list、apply、rollback、status 四个子命令。版本放在 ./releases 目录下，每个子目录是一个版本，./current 软链接指向当前版本：list 列出所有版本，apply <版本> 把 current 指向它，rollback 切回上一个版本，status 输出当前版本。
