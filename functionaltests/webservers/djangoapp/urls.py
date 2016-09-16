from django.conf.urls import url

from . import views

urlpatterns = [
    url(r'^context$', views.context, name='context'),
    url(r'^resolve$', views.resolve, name='resolve'),
]
