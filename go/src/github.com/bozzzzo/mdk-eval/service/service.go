package main

import (
	"fmt"
	"github.com/datawire/mdk_go/mdk"
)

func main() {
	m := mdk.Start()
	m2 := mdk.Start()
	fmt.Printf("Whee a service\n")
	s := m.Session()
	s.Log("zero")
	s1 := m2.Join(s.Externalize())
	s1.Log("zero one")
	s2 := m.Session()
	s2.Log("twoo")
	m2.Stop()
	m.Stop()
}
