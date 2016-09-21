package impl

import "fmt"

type Session struct {
	mdk *MDK
	id string
}

func Session__Constructor(mdk *MDK, id string) *Session {
	s := new(Session)
	s.mdk = mdk
	s.id = id
	return s
}

func (self *Session) Externalize() string { return "id"; }

func (self *Session) Log(msg string) {
	fmt.Println("%v %v", self, msg);
}
