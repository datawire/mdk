package mdk

type Api_Plugin interface {
	Init(mdk Api_MDK)
	OnSession(session Api_Session)
}
