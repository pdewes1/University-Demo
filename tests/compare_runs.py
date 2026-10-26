"""
Compare two Agentforce Testing Center result exports side by side, for example the all-Apex agent
against the hybrid (Flow) agent run on the same cases.

Usage:
  python tests/compare_runs.py <apex-results.csv> <hybrid-results.csv> [--labels Apex Hybrid]

Export each run from Testing Center (the results CSV), then point this at both files. Cases are
matched by utterance. Prints pass counts per check (action, topic, outcome), cases only one run
has, and every case where the two runs disagree, so you can read those responses first.
Standard library only.
"""
import argparse
import csv
import sys

CHECKS = [
    ("Action", "Action Test Result Status"),
    ("Topic", "Subagent Test Result Status"),
    ("Outcome", "Outcome Test Result Status"),
]


def load(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    missing = [col for _, col in CHECKS if rows and col not in rows[0]]
    if missing:
        sys.exit(f"{path}: missing columns {missing}. Is this a Testing Center results export?")
    return {r["Utterance"].strip(): r for r in rows}


def passed(row, col):
    return (row.get(col) or "").strip().upper() == "SUCCESS"


def latency(row):
    try:
        return float(row.get("Output Latency Milliseconds") or "")
    except ValueError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("first")
    ap.add_argument("second")
    ap.add_argument("--labels", nargs=2, default=["Apex", "Hybrid"])
    args = ap.parse_args()
    a, b = load(args.first), load(args.second)
    la, lb = args.labels
    shared = [u for u in a if u in b]

    print(f"{la}: {len(a)} cases   {lb}: {len(b)} cases   in both: {len(shared)}\n")
    print(f"{'Check (cases in both)':<24}{la:>10}{lb:>10}")
    for name, col in CHECKS:
        scored = [u for u in shared if a[u].get(col) and b[u].get(col)]
        pa = sum(passed(a[u], col) for u in scored)
        pb = sum(passed(b[u], col) for u in scored)
        print(f"{name:<24}{f'{pa}/{len(scored)}':>10}{f'{pb}/{len(scored)}':>10}")
    for label, rows in ((la, a), (lb, b)):
        lat = sorted(x for x in (latency(rows[u]) for u in shared) if x is not None)
        if lat:
            print(f"{'Median latency, ' + label:<24}{lat[len(lat) // 2] / 1000:>9.1f}s")

    only_b = [u for u in b if u not in a]
    if only_b:
        print(f"\nOnly in {lb} ({len(only_b)}):")
        for u in only_b:
            r = b[u]
            marks = " ".join(f"{n[0]}:{'pass' if passed(r, c) else 'FAIL'}" for n, c in CHECKS if r.get(c))
            print(f"  [{marks}] {u}")
    only_a = [u for u in a if u not in b]
    if only_a:
        print(f"\nOnly in {la} ({len(only_a)}):")
        for u in only_a:
            print(f"  {u}")

    diffs = []
    for u in shared:
        changed = [n for n, c in CHECKS if passed(a[u], c) != passed(b[u], c) and a[u].get(c) and b[u].get(c)]
        if changed:
            diffs.append((u, changed))
    print(f"\nCases where the runs disagree ({len(diffs)}):")
    if not diffs:
        print("  none")
    for u, changed in diffs:
        print(f"\n  {u}")
        for n, c in CHECKS:
            if n in changed:
                print(f"    {n}: {la} {'pass' if passed(a[u], c) else 'FAIL'}, {lb} {'pass' if passed(b[u], c) else 'FAIL'}")
        if "Action" in changed:
            print(f"    actions  {la}: {a[u].get('Actual Action')}   {lb}: {b[u].get('Actual Action')}")
        for label, r in ((la, a[u]), (lb, b[u])):
            out = (r.get("Actual Outcome") or "").replace("\n", " ")
            print(f"    {label} said: {out[:220]}{'...' if len(out) > 220 else ''}")


if __name__ == "__main__":
    main()
