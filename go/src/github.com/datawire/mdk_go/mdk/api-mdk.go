package mdk

type Api_MDK interface {
	Start()
	Session() Api_Session
	Join(id string) Api_Session
	Register(plugin Api_Plugin)
	Stop()
}
