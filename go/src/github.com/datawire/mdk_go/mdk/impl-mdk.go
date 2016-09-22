package mdk

import "fmt"

type Impl_MDK struct {
	count int
	sessions int
	plugin Api_Plugin
}

var instances int

func Impl_MDK__Constructor() *Impl_MDK {
	mdk := new(Impl_MDK);
	mdk.count = instances
	instances++
	return mdk
}

func (self *Impl_MDK) Start() {
	fmt.Printf("I am %v impl start\n", self)
}

func (self *Impl_MDK) Session() Api_Session {
	self.sessions++;
	return self._session(Helpers_Uuid())
}

func (self *Impl_MDK) _session(id string) Api_Session {
	var s Api_Session;
	s = Impl_Session__Constructor(self, id)
	if self.plugin != nil {
		self.plugin.OnSession(s)
	}
	return s;
}

func (self *Impl_MDK) Join(id string) Api_Session {
	self.sessions++;
	return self._session(id)
}

func (self *Impl_MDK) Stop() {
	fmt.Printf("I the %v haz stoppped\n", self);
}

func (self *Impl_MDK) Register(plugin Api_Plugin) {
	self.plugin = plugin
	fmt.Printf("I got a new plugin %v for myself %v\n", plugin, self);
	self.plugin.Init(self)
}

func (self *Impl_MDK) String() string {
	return fmt.Sprintf("MDK(%v %v)", self.count, self.sessions);
}
