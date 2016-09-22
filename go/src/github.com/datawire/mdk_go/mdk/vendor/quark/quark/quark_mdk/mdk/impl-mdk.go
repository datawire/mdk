package mdk

import "fmt"

type Mdk_Impl_MDK struct {
	count int
	sessions int
	plugin Mdk_Api_Plugin
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
	return self._session(Mdk_Helpers_Uuid())
}

func (self *Mdk_Impl_MDK) _session(id string) Mdk_Api_Session {
	var s Mdk_Api_Session;
	s = Mdk_Impl_Session__Constructor(self, id)
	if self.plugin != nil {
		self.plugin.OnSession(s)
	}
	return s;
}

func (self *Mdk_Impl_MDK) Join(id string) Mdk_Api_Session {
	self.sessions++;
	return self._session(id)
}

func (self *Mdk_Impl_MDK) Stop() {
	fmt.Printf("I the %v haz stoppped\n", self);
}

func (self *Mdk_Impl_MDK) Register(plugin Mdk_Api_Plugin) {
	self.plugin = plugin
	fmt.Printf("I got a new plugin %v for myself %v\n", plugin, self);
	self.plugin.Init(self)
}

func (self *Mdk_Impl_MDK) String() string {
	return fmt.Sprintf("MDK(%v %v)", self.count, self.sessions);
}
