#!/usr/bin/env python3
"""Ranks the last comparison by how much of each control's own region is wrong.

Two columns on purpose: the normal state alone, and every state. A change that
helps one and hurts the other is a change that traded one bug for another.
"""
import json, sys, collections
root = sys.argv[1] if len(sys.argv) > 1 else "build/compare"
rows = json.load(open(f"{root}/report.json"))["rows"]
rows = [r for r in rows if r.get("status") == "compared"]
by, byn, vis = (collections.defaultdict(list), collections.defaultdict(list),
                collections.defaultdict(list))
for r in rows:
    by[r["control"]].append(r["wrongShare"])
    vis[r["control"]].append(r.get("visibleShare", 0.0))
    if r["state"] == "normal":
        byn[r["control"]].append(r["wrongShare"])


def mean(values):
    return sum(values) / len(values) * 100 if values else 0.0


print(f"{'control':<20}{'normal%':>9}{'all%':>9}{'visible%':>10}{'shots':>7}")
order = sorted(by, key=lambda k: -mean(byn.get(k, [])))
for k in order:
    print(f"{k:<20}{mean(byn.get(k, [])):9.2f}{mean(by[k]):9.2f}{mean(vis[k]):10.2f}{len(by[k]):7d}")
print(f"{'MEAN':<20}{mean([w for k in byn for w in byn[k]]):9.2f}"
      f"{mean([r['wrongShare'] for r in rows]):9.2f}"
      f"{mean([r.get('visibleShare', 0.0) for r in rows]):10.2f}{len(rows):7d}")
print("\nnormal% and all% count any channel off by more than 2, which is the\n"
      "acceptance target. visible% counts only pixels off by more than 16.")
focused = [r for r in rows if r["state"] == "focused"]
if focused:
    print(f"the focused rows ({mean([r['wrongShare'] for r in focused]):.2f}% of them) are measured against a\n"
          "reference the capture does not draw correctly — see tools/reference/README.md.")
