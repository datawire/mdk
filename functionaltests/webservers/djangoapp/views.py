from json import dumps

from django.http import HttpResponse

def index(request):
    return HttpResponse("")

def context(request):
    return HttpResponse(request.mdk_session.externalize())

def resolve(request):
    node = request.mdk_session.resolve("service1", "1.0")
    # This should be a RecordingFailurePolicy:
    policy = request.mdk_session._mdk._disco.failurePolicy(node)
    result = dumps({node.address: [policy.successes, policy.failures]})
    if request.GET.get("error"):
        raise RuntimeError("Erroring as requested.")
    else:
        return HttpResponse(result)

def timeout(request):
    return HttpResponse(dumps(request.mdk_session.getRemainingTime()))
