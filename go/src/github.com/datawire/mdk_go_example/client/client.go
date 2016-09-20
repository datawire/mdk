package main

import (
	"fmt"
	"github.com/datawire/mdk_go/mdk"
)

func main() {
	mdk.Start()
	fmt.Print("Whee\n")
	mdk.Stop()
}
