package api

type Session interface {
	Externalize() string
	Log(msg string)
}
