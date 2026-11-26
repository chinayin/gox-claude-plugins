package main

import (
	"flag"
	"fmt"
	"os"
)

var (
	version = "dev"
	commit  = "unknown"
	date    = "unknown"
)

func main() {
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Println(version, commit, date)
		return
	}
	fmt.Fprintln(os.Stderr, "demo-svc: nothing to serve yet")
}
