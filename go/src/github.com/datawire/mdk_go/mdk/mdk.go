package mdk

import "quark/quark/quark_mdk/mdk"

type MDK interface {
	mdk.Mdk_Api_MDK
}

type Session interface {
	mdk.Mdk_Api_Session
}

type Plugin interface {
	mdk.Mdk_Api_Plugin
}


func Start() MDK {
	mdk := mdk.Mdk_Api_GetMDK();
	mdk.Start();
	return mdk;
}

func Init() MDK {
	return mdk.Mdk_Api_GetMDK();
}
