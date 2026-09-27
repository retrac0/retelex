import sys,re
for fn in sys.argv[1:]:
    last={}; lags=[]
    for l in open(fn):
        m=re.match(r'C12T (\d+) (\S+) .*?\bt=(\d+)',l)
        if not m: continue
        ex,kind,t=m.group(1),m.group(2),int(m.group(3))
        if kind=='f2': last[ex]=t
        elif kind=='rise' and ' f2=1 ' in l: lags.append((ex,(t-last[ex])/1e9))
        elif kind=='EARLY': print(fn,'EARLY',l.strip())
    print(fn, 'n=%d'%len(lags), 'min %.3f max %.3f ms'%(min(x[1] for x in lags),max(x[1] for x in lags)) if lags else '', sorted(set(round(x[1],2) for x in lags)))
