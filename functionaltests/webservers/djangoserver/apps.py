from mdk.django import MDKAppConfig

class MyMDKAppConfig(MDKAppConfig):
    def mdk_ready(self, mdk):
        mdk.setDefaultTimeout(10.0)
