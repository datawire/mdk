package mdk

type Mdk_Api_MDK interface {
	Start()
	Session() Mdk_Api_Session
	Join(id string) Mdk_Api_Session
	Stop()
}
