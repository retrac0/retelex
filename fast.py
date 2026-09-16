import ctypes, numpy as np, os
_L = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libphyfast.so'))
_L.c_slice_hyst.argtypes=[np.ctypeslib.ndpointer(np.float64),ctypes.c_long,ctypes.c_double,np.ctypeslib.ndpointer(np.uint8)]
_L.c_dpll_decode.restype=ctypes.c_long
_L.c_dpll_decode.argtypes=[np.ctypeslib.ndpointer(np.uint8),ctypes.c_long,ctypes.c_int,ctypes.c_int,ctypes.c_int,
                           np.ctypeslib.ndpointer(np.uint8),np.ctypeslib.ndpointer(np.int64),ctypes.c_long]
_L.c_ami_decode.restype=ctypes.c_long
_L.c_ami_decode.argtypes=[np.ctypeslib.ndpointer(np.float64),ctypes.c_long,ctypes.c_int,ctypes.c_double,
                          np.ctypeslib.ndpointer(np.uint8),ctypes.c_long]

def slice_hyst(x,h=0.05):
    x=np.ascontiguousarray(x,np.float64); o=np.empty(len(x),np.uint8)
    _L.c_slice_hyst(x,len(x),h,o); return o

def dpll_decode(w,OS,win=None,lock_after=32):
    w=np.ascontiguousarray(w,np.uint8); win=OS//4 if win is None else win
    b=np.empty(len(w)//max(OS//2,1)+64,np.uint8); st=np.zeros(3,np.int64)
    n=_L.c_dpll_decode(w,len(w),OS,win,lock_after,b,st,len(b))
    return b[:n], dict(resyncs=int(st[0]),nudges=int(st[1]),
                       lock_sample=(None if st[2]<0 else int(st[2])))

def ami_decode(x,OS,thresh=0.5,peak=None):
    x=np.ascontiguousarray(x,np.float64)
    if peak is None: peak=np.percentile(np.abs(x),99)
    b=np.empty(len(x)//max(OS//2,1)+64,np.uint8)
    n=_L.c_ami_decode(x,len(x),OS,thresh*peak,b,len(b))
    return b[:n]

def dm_encode(bits):
    b=np.asarray(bits,np.int64); z=(b==0).astype(np.int64)
    Z=np.concatenate([[0],np.cumsum(z)[:-1]]); i=np.arange(len(b))
    fh=((i+1)+Z)&1; sh=fh^z
    o=np.empty(2*len(b),np.uint8); o[0::2]=fh; o[1::2]=sh; return o

def ami_encode(bits):
    b=np.asarray(bits,np.int64); k=np.cumsum(b)-1
    return np.where(b==1,np.where(k%2==0,1.0,-1.0),0.0)

_L.c_apll_decode.restype=ctypes.c_long
_L.c_apll_decode.argtypes=[np.ctypeslib.ndpointer(np.uint8),ctypes.c_long,ctypes.c_double,
                           ctypes.c_double,ctypes.c_double,np.ctypeslib.ndpointer(np.uint8),ctypes.c_long]
def apll_decode(w,spb,kp=0.15,ki=0.002):
    w=np.ascontiguousarray(w,np.uint8); b=np.empty(int(len(w)/spb*6)+64,np.uint8)
    n=_L.c_apll_decode(w,len(w),float(spb),kp,ki,b,len(b)); return b[:n]

_L.c_mono_decode.restype=ctypes.c_long
_L.c_mono_decode.argtypes=[np.ctypeslib.ndpointer(np.uint8),ctypes.c_long,ctypes.c_double,
                           ctypes.c_double,ctypes.c_double,np.ctypeslib.ndpointer(np.uint8),ctypes.c_long]
def mono_decode(w,spb,thr=0.75,dead=0.25):
    w=np.ascontiguousarray(w,np.uint8); b=np.empty(int(len(w)/(spb*dead))+64,np.uint8)
    n=_L.c_mono_decode(w,len(w),float(spb),thr,dead,b,len(b)); return b[:n]
