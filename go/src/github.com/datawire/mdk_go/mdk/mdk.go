package mdk

import "fmt"
import "github.com/datawire/mdk_go/mdk/discovery"
import "quark/quark/quark_mdk"

interface MDK (
	quark_mdk.MdkAPI
)


func Start() {
	fmt.Print("MDK Start\n")
        discovery.Discoball()
}

func Stop() {
	fmt.Print("MDK Stop\n")
}
