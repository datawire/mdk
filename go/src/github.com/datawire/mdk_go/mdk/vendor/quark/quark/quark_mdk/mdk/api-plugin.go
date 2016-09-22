package mdk

type Mdk_Api_Plugin interface {
	Init(mdk Mdk_Api_MDK)
	OnSession(session Mdk_Api_Session)
}
