from mdk.django import MDKAppConfig

class MyMDKAppConfig(MDKAppConfig):
    def mdk_ready(self, mdk):
        mdk.setDefaultDeadline(10.0)
