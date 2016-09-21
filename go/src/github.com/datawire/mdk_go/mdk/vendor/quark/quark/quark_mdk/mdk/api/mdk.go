package api

type MDK interface {
	Start()
	//Session() Session
	Join(id string) Session
	Stop()
}
