#!/usr/bin/env python3
"""Emit synthetic MCP tools/list arrays for tooldoc test scenarios."""
import json
import sys


def tool(name, desc, params):
    # params: list of (pname, ptype, pdesc, enum)
    props = {}
    for pn, pt, pd, en in params:
        p = {"type": pt}
        if pd:
            p["description"] = pd
        if en:
            p["enum"] = en
        props[pn] = p
    return {"name": name, "description": desc,
            "inputSchema": {"type": "object", "properties": props}}


def scenario(name):
    if name == "clean":
        out = [tool("search", "Search the index for a query string.",
                    [("query", "string", "The text to search for.", None),
                     ("limit", "integer", "Max results to return.", None)])]
    elif name == "no_tool_desc":
        out = [tool("frobnicate", "", [("x", "string", "the thing", None)])]
    elif name == "guess_prone":
        # a free-form string param with no description and no enum
        out = [tool("run", "Run a job.", [("mode", "string", "", None)])]
    elif name == "thin":
        out = [tool("go", "go", [("p", "string", "the path", None)])]
    elif name == "collision_a":
        out = [tool("search", "Search server A.", [("q", "string", "query", None)])]
    elif name == "collision_b":
        out = [tool("search", "Search server B.", [("q", "string", "query", None)])]
    else:
        sys.stderr.write(f"unknown scenario: {name}\n"); sys.exit(2)
    print(json.dumps(out))


if __name__ == "__main__":
    scenario(sys.argv[1] if len(sys.argv) > 1 else "clean")
