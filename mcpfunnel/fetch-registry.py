import json, urllib.request, urllib.error
def get(url):
    try:
        with urllib.request.urlopen(url, timeout=20) as r: return json.loads(r.read())
    except Exception as e: return None
base="https://registry.modelcontextprotocol.io/v0/servers"
servers=[]; cursor=None; pages=0
while pages<8:
    url=base+"?limit=100"+(f"&cursor={cursor}" if cursor else "")
    d=get(url)
    if not d: break
    servers+=d.get("servers",[])
    cursor=(d.get("metadata") or {}).get("nextCursor") or (d.get("metadata") or {}).get("next_cursor")
    pages+=1
    if not cursor: break
print(f"pulled {len(servers)} server records over {pages} pages")
# dedupe to latest per name
latest={}
for s in servers:
    srv=s.get("server",{}); name=srv.get("name")
    meta=(s.get("_meta",{}) or {}).get("io.modelcontextprotocol.registry/official",{}) or {}
    if name and (meta.get("isLatest") or name not in latest):
        latest[name]=s
print(f"unique latest servers: {len(latest)}")
# composition
npm=pypi=oci=remote=other=0
pkgex=None
for s in latest.values():
    srv=s.get("server",{})
    pkgs=srv.get("packages") or []
    if not pkgs and srv.get("remotes"): remote+=1; continue
    regs=set()
    for p in pkgs:
        rt=p.get("registryType") or p.get("registry_name") or p.get("registry") or ""
        regs.add(rt.lower())
        if rt.lower() in ("npm","pypi") and pkgex is None: pkgex=p
    if "npm" in regs: npm+=1
    elif "pypi" in regs: pypi+=1
    elif "oci" in regs or "docker" in regs: oci+=1
    else: other+=1
print(f"npm={npm} pypi={pypi} oci/docker={oci} remote-only={remote} other={other}")
print("example package entry:", json.dumps(pkgex, indent=2)[:600] if pkgex else "none")
json.dump(list(latest.values()), open("/tmp/reg_servers.json","w"))
