package api

import "quark/quark/quark_mdk/mdk/impl"

func GetMDK() MDK {
	return impl.MDK__Constructor()
}
