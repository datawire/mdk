package mdk

import "quark/quark/quark_mdk/mdk/api"

type MDK interface {
	api.MDK
}


func Start() MDK {
	mdk := api.GetMDK();
	mdk.Start();
	return mdk;
}

func Stop() {
}
