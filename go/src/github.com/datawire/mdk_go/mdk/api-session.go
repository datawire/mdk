package mdk

type Api_Session interface {
	Externalize() string
	Log(msg string)
}
