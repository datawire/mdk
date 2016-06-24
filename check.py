#!python

from mdk import SharedContext

def log(ctx, msg):
    ctx.tick();
    print("%s -- %s" % (ctx.key(), msg))

def enter(ctx):
    c2 = ctx.enter();
    log(ctx, "entered");

def leave(ctx):
    c2 = ctx.leave();
    log(ctx, "left");

ctx = SharedContext("origin1");
log(ctx, "CREATED!")

log(ctx, "step ctx")

c2 = enter(ctx)
log(c2, "step c2")
log(ctx, "step ctx")
log(c2, "step c2")

c3 = enter(ctx)
log(c3, "step c3")
log(ctx, "step ctx")
log(c2, "step c2")
log(c3, "step c3")
log(c2, "step c2")
log(c2, "step c2")

c4 = enter(c2)
log(c4, "step c4")
log(c2, "step c2")
log(ctx, "step ctx")
log(c3, "step c3")
log(ctx, "step ctx")
log(c4, "step c4")

log(ctx, "step ctx")
leave(c4)
log(c2, "step c2")
leave(c3)
log(ctx, "step")
leave(ctx)
