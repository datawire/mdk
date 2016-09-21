package mdk

import "fmt"

type Mdk_Impl_MDK struct {
	count int
	sessions int
}

var instances int

func Mdk_Impl_MDK__Constructor() *Mdk_Impl_MDK {
	mdk := new(Mdk_Impl_MDK);
	mdk.count = instances
	instances++
	return mdk
}

func (self *Mdk_Impl_MDK) Start() {
	fmt.Printf("I am %v impl start\n", self)
}

func (self *Mdk_Impl_MDK) Session() Mdk_Api_Session {
	self.sessions++;
	return Mdk_Impl_Session__Constructor(self, Mdk_Helpers_Uuid())
}

func (self *Mdk_Impl_MDK) Join(id string) Mdk_Api_Session {
	self.sessions++;
	return Mdk_Impl_Session__Constructor(self, id)
}

func (self *Mdk_Impl_MDK) Stop() {
	fmt.Printf("I the %v haz stoppped\n", self);
}

func (self *Mdk_Impl_MDK) String() string {
	return fmt.Sprintf("MDK(%v %v)", self.count, self.sessions);
}
