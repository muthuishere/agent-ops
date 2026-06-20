import json, urllib.request, urllib.error, itertools
POP = ["react","express","lodash","axios","next","vue","redux","mongoose","moment","chalk",
       "webpack","eslint","jest","vite","zod","prisma","socket","cors","passport","jsonwebtoken",
       "bcrypt","dotenv","uuid","commander","yargs","nodemon","puppeteer","playwright","winston"]
SUFFIX = ["helper","utils","middleware","client","sdk","config","plugin","wrapper"]
def get(url):
    try:
        with urllib.request.urlopen(url, timeout=12) as r: return r.status, r.read()
    except urllib.error.HTTPError as e: return e.code, b""
    except Exception: return None, b""
def dls(name):
    s,b=get(f"https://api.npmjs.org/downloads/point/last-month/{name}")
    if s==200:
        try: return json.loads(b).get("downloads",0)
        except: return 0
    return 0
# build conflation candidates: popA-popB and pop-suffix
cands=[]
for a,b in itertools.combinations(POP,2):
    cands.append(f"{a}-{b}")
import random
random.seed  # not used; deterministic slice
cands = cands[:50] + [f"{p}-{s}" for p in POP[:10] for s in SUFFIX[:4]]
registered=[]; checked=0
for name in cands:
    checked+=1
    s,b=get(f"https://registry.npmjs.org/{name}")
    if s==200:
        try: created=json.loads(b).get("time",{}).get("created","")[:10]
        except: created=""
        d=dls(name)
        registered.append((name,d,created))
print(f"checked {checked} conflation-pattern names")
print(f"REGISTERED on npm: {len(registered)} ({100*len(registered)//checked}%)")
low=[r for r in registered if r[1]<50]
print(f"  of those, {len(low)} have <50 downloads/month (obscure -> confusion/squat risk)")
print("examples (name, monthly downloads, created):")
for n,d,c in sorted(registered,key=lambda x:x[1])[:12]:
    print(f"   {n:<28} {d:>10} dl   {c}")
