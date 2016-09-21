package mdk

type Mdk_Api_Session interface {
	Externalize() string
	Log(msg string)
}
