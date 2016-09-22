package main

import (
	"fmt"
	"github.com/datawire/mdk_go/mdk"
)

type Plug struct {
}

func (self *Plug) Init(m mdk.MDK) {
	fmt.Printf("service plugin %v got initialized by %v\n", self, m);
}

func (self *Plug) OnSession(s mdk.Session) {
	fmt.Printf("oh, look a new session %v\n", s);
}

func (self *Plug) String() string {
	return "A-Plug"
}

func main() {
	fmt.Printf("Whee a service\n")
	p := new(Plug)
	m := mdk.Start()
	m.Register(p)
	fmt.Printf("Second mdk coming up...\n")
	m2 := mdk.Start()
	m2.Register(p);
	s := m.Session()
	s.Log("zero")
	s1 := m2.Join(s.Externalize())
	s1.Log("zero one")
	s2 := m.Session()
	s2.Log("twoo")
	fmt.Printf("Cleaning up...\n")
	m2.Stop()
	fmt.Printf("Almost there...\n")
	m.Stop()
	fmt.Printf("finito\n")
}
