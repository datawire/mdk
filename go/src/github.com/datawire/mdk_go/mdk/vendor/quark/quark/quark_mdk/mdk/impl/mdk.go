package impl

import "fmt"
import "quark/quark/quark_mdk/mdk/helpers"

type MDK struct {
	count int
}

var instances int

func MDK__Constructor() *MDK {
	mdk := new(MDK);
	mdk.count = instances
	instances++
	return mdk
}

func (self *MDK) Start() {
	fmt.Println("I am MDK impl start")
}

func (self *MDK) Session() *Session {
	return Session__Constructor(self, helpers.Uuid())
}

func (self *MDK) Join(id string) *Session {
	return Session__Constructor(self, id)
}

func (self *MDK) Stop() {
}
