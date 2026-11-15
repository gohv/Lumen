import numpy as np, sys, os
from PIL import Image
out = sys.argv[1]; prev = sys.argv[2]; os.makedirs(prev, exist_ok=True)
SS = 4
def grid(n):
    m = n*SS
    c = (np.arange(m)+0.5)/SS - n/2
    x, y = np.meshgrid(c, c)
    return x, -y
def down(a, n):
    return a.reshape(n, SS, n, SS).mean(axis=(1,3))
def save(name, alpha, n, rgb=(1,1,1)):
    a = np.clip(alpha,0,1)
    img = np.zeros((n,n,4))
    img[...,0], img[...,1], img[...,2] = rgb[0], rgb[1], rgb[2]
    if callable(rgb): pass
    img[...,3] = a
    im = Image.fromarray((img*255+0.5).astype(np.uint8), "RGBA")
    im.save(f"{out}/{name}.tga", compression=None, orientation=-1)
    bg = Image.new("RGBA", im.size, (24,26,34,255)); bg.alpha_composite(im); bg.save(f"{prev}/{name}.png")
def save_rgba(name, img):
    im = Image.fromarray((np.clip(img,0,1)*255+0.5).astype(np.uint8), "RGBA")
    im.save(f"{out}/{name}.tga", compression=None, orientation=-1)
    bg = Image.new("RGBA", im.size, (24,26,34,255)); bg.alpha_composite(im); bg.save(f"{prev}/{name}.png")

# filled circle (mask / swipe / backdrop)
n=128; x,y=grid(n); r=np.hypot(x,y)
save("circle", down((r<=62).astype(float), n), n)
# rings
save("ring", down(((r<=63)&(r>=56)).astype(float), n), n)
save("ring_bold", down(((r<=63)&(r>=53)).astype(float), n), n)
save("ring_thin", down(((r<=63)&(r>=60)).astype(float), n), n)
# soft halo glow (256): gaussian around radius 0.5*R
n=256; x,y=grid(n); r=np.hypot(x,y)/128
save("glow", down(np.exp(-((r-0.52)/0.16)**2) * (r<1), n), n)
# radial bloom (filled soft)
save("bloom", down(np.exp(-(r/0.45)**2) * (r<1), n), n)
# comet arc: ring with alpha rising along angle, bright head
n=256; x,y=grid(n); r=np.hypot(x,y)/128
ang = (np.arctan2(x, y) % (2*np.pi)) / (2*np.pi)     # 0 at top, clockwise
tail = ang**2.2
band = np.exp(-((r-0.80)/0.07)**2)
head = np.exp(-(((x/128) - 0.0)**2 + ((y/128) - 0.80)**2)/0.004)
a = np.clip(band*tail + head*1.2, 0, 1) * (r<1)
save("comet", down(a, n), n)
# glass shine: elliptical highlight in upper half, inside circle
n=128; x,y=grid(n); r=np.hypot(x,y)
e = np.hypot(x/1.0, (y-26)/0.62)
a = np.clip(1 - e/46, 0, 1)**1.6 * 0.55 * (r<=60)
save("shine", down(a, n), n)
# drop shadow (soft black disk)
n=128; x,y=grid(n); r=np.hypot(x,y)/64
img = np.zeros((n*SS,n*SS,4)); img[...,3] = np.clip(1-(r-0.70)/0.30,0,1)**2 * 0.85
save_rgba("shadow", np.stack([down(img[...,i],n) for i in range(4)],-1))
# xp bar fill gradient & shimmer (horizontal)
w,h=256,16
xs=np.linspace(0,1,w)[None,:].repeat(h,0)
save_rgba("shimmer", np.dstack([np.ones((h,w))]*3 + [np.exp(-((xs-0.5)/0.18)**2)*0.9]))
# addon icon: aurora gradient ring on dark disk
n=128; x,y=grid(n); r=np.hypot(x,y); ang=(np.arctan2(x,y)%(2*np.pi))/(2*np.pi)
stops=np.array([[0.55,0.36,0.96],[0.93,0.28,0.60],[0.98,0.62,0.12],[0.20,0.90,0.60],[0.55,0.36,0.96]])
t=ang*4; i=np.floor(t).astype(int).clip(0,3); f=(t-i)[...,None]
col=stops[i]*(1-f)+stops[i+1]*f
ring=((r<=60)&(r>=48)).astype(float); disk=(r<48).astype(float)
img=np.zeros((n*SS,n*SS,4)); img[...,:3]=col*ring[...,None]+np.array([0.07,0.08,0.11])*disk[...,None]
img[...,3]=np.clip(ring+disk,0,1)
save_rgba("icon", np.stack([down(img[...,k],n) for k in range(4)],-1))

# ---- avatar orb ----
# band: opaque glass ring from r=0.69R to R (hides the square model corners)
n=256; x,y=grid(n); r=np.hypot(x,y)/128
inside=((r>=0.685)&(r<=0.99)).astype(float)
shade=0.55+0.35*(y/128)            # lighter at top
shade=shade*(0.75+0.25*np.clip((r-0.685)/0.3,0,1))  # darker toward the window
img=np.zeros((n*SS,n*SS,4)); img[...,0]=img[...,1]=img[...,2]=np.clip(shade,0,1); img[...,3]=inside
save_rgba("band", np.stack([down(img[...,k],n) for k in range(4)],-1))
# liquid fill: vertical gradient, brighter near the surface
w,h=64,128
t=np.linspace(1,0,h)[:,None].repeat(w,1)    # 1 at top row
v=0.62+0.38*t**3
save_rgba("liquid", np.dstack([v,v,v,0.55+0.4*t]))
# wave crest: tileable, period 128 px over width 256
w,h=256,32
xs=np.arange(w)[None,:].repeat(h,0); ys=np.arange(h)[:,None].repeat(w,1)
crest=16+3.5*np.sin(xs/128*2*np.pi)+1.5*np.sin(xs/64*2*np.pi+1)
d=ys-crest
a=np.where(d<0, np.exp(-(d/1.4)**2), np.exp(-(d/7)**2)*0.55+np.exp(-(d/1.4)**2)*0.45)
save_rgba("wave", np.dstack([np.ones((h,w))]*3+[np.clip(a,0,1)]))
