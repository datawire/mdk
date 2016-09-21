package mdk

import "fmt"

type Mdk_Impl_Session struct {
	mdk *Mdk_Impl_MDK
	id string
}

func Mdk_Impl_Session__Constructor(mdk *Mdk_Impl_MDK, id string) *Mdk_Impl_Session {
	s := new(Mdk_Impl_Session)
	s.mdk = mdk
	s.id = id
	return s
}

func (self *Mdk_Impl_Session) Externalize() string { return "id"; }

func (self *Mdk_Impl_Session) Log(msg string) {
	fmt.Printf("%v:   %v\n", self, msg);
}

func (self *Mdk_Impl_Session) String() string {
	return fmt.Sprintf("Session(%v %v)", self.mdk, self.id);
}
