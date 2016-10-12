from django.conf.urls import url

from . import views

urlpatterns = [
    url(r'^context$', views.context, name='context'),
    url(r'^resolve$', views.resolve, name='resolve'),
    url(r'^timeout$', views.timeout, name='timeout'),
    url(r'^$', views.index, name='index')
]
