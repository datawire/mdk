package mdk

import "fmt"

type Impl_Session struct {
	mdk *Impl_MDK
	id string
}

func Impl_Session__Constructor(mdk *Impl_MDK, id string) *Impl_Session {
	s := new(Impl_Session)
	s.mdk = mdk
	s.id = id
	return s
}

func (self *Impl_Session) Externalize() string { return "id"; }

func (self *Impl_Session) Log(msg string) {
	fmt.Printf("%v:   %v\n", self, msg);
}

func (self *Impl_Session) String() string {
	return fmt.Sprintf("Session(%v %v)", self.mdk, self.id);
}
