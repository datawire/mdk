package mdk

import "quark/quark/quark_mdk/mdk"

type MDK interface {
	mdk.Mdk_Api_MDK
}


func Start() MDK {
	mdk := mdk.Mdk_Api_GetMDK();
	mdk.Start();
	return mdk;
}

func Init() MDK {
	return mdk.Mdk_Api_GetMDK();
}
