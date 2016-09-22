package mdk

func Start() Api_MDK {
	var m Api_MDK = Init()
	m.Start()
	return m
}
