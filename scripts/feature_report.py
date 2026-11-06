#!/usr/bin/env python3
"""Maps test results to features.json and writes a verification report.

Usage: feature_report.py <run-dir> [--only id,id]

Reads from <run-dir>:
  core-swift-testing.xml   swift test --xunit-output (VaasiCoreTests)
  *.xcresult               xcodebuild result bundles (VaasiTests, VaasiUITests)
  static.json              {"static/<check>": "Passed" | "Failed"}
and verification/agent-checks.json for agent-driven checks.

Exits 1 when any "done" feature has a missing or failing test, or a failing
or missing agent check.
"""
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def core_results(run: Path) -> dict:
    results = {}
    for xml in run.glob("core*.xml"):
        for case in ET.parse(xml).getroot().iter("testcase"):
            suite = case.get("classname", "").split(".")[-1]
            bundle = case.get("classname", "").split(".")[0]
            failed = case.find("failure") is not None or case.find("error") is not None
            results[f"{bundle}/{suite}/{case.get('name')}"] = "Failed" if failed else "Passed"
    return results


def xcresult_results(run: Path) -> dict:
    results = {}
    for bundle in run.glob("*.xcresult"):
        out = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--compact"],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            continue
        data = json.loads(out.stdout)

        def walk(node, target=None):
            kind = node.get("nodeType")
            if kind in ("Unit test bundle", "UI test bundle"):
                target = node.get("name")
            if kind == "Test Case" and target and node.get("nodeIdentifier"):
                results[f"{target}/{node['nodeIdentifier']}"] = node.get("result", "Unknown")
            for child in node.get("children", []):
                walk(child, target)

        for node in data.get("testNodes", []):
            walk(node)
    return results


def static_results(run: Path) -> dict:
    path = run / "static.json"
    return json.loads(path.read_text()) if path.exists() else {}


def agent_results() -> dict:
    path = ROOT / "verification" / "agent-checks.json"
    if not path.exists():
        return {}
    return {c["id"]: c for c in json.loads(path.read_text()).get("checks", [])}


def main() -> int:
    run = Path(sys.argv[1]).resolve()
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))

    manifest = json.loads((ROOT / "features.json").read_text())
    results = {**core_results(run), **xcresult_results(run), **static_results(run)}
    agents = agent_results()

    rows, problems = [], []
    counts = {"verified": 0, "failing": 0, "deferred": 0}
    for feature in manifest["features"]:
        if only and feature["id"] not in only:
            continue
        if feature["status"] != "done":
            counts["deferred"] += 1
            rows.append((feature, "➖ " + feature["status"], feature.get("note", "")))
            continue
        tests = feature.get("tests", [])
        agent_ids = feature.get("agent", [])
        if not tests and not agent_ids:
            problems.append(f"{feature['id']}: no evidence listed")
        details, ok = [], True
        for test in tests:
            result = results.get(test)
            if result is None:
                ok = False
                details.append(f"missing `{test}`")
                problems.append(f"{feature['id']}: test not found in this run: {test}")
            elif result != "Passed":
                ok = False
                details.append(f"{result.lower()} `{test}`")
                problems.append(f"{feature['id']}: {result}: {test}")
        passed_tests = sum(1 for t in tests if results.get(t) == "Passed")
        for check_id in agent_ids:
            check = agents.get(check_id)
            if check is None:
                ok = False
                details.append(f"agent check `{check_id}` not recorded")
                problems.append(f"{feature['id']}: agent check not recorded: {check_id}")
            elif check.get("result") != "pass":
                ok = False
                details.append(f"agent check `{check_id}`: {check.get('result')}")
                problems.append(f"{feature['id']}: agent check {check_id}: {check.get('result')}")
        summary = f"{passed_tests}/{len(tests)} tests"
        if agent_ids:
            summary += f", {sum(1 for a in agent_ids if agents.get(a, {}).get('result') == 'pass')}/{len(agent_ids)} agent checks"
        counts["verified" if ok else "failing"] += 1
        rows.append((feature, ("✅ " if ok else "❌ ") + summary, "; ".join(details)))

    lines = [
        "# Feature verification",
        "",
        f"Run: `{run.relative_to(ROOT) if run.is_relative_to(ROOT) else run}`",
        "",
        f"**{counts['verified']} verified · {counts['failing']} failing · {counts['deferred']} deferred or skipped**",
        "",
        "| Feature | Status | Notes |",
        "|---|---|---|",
    ]
    for feature, status, note in rows:
        lines.append(f"| {feature['name']} (`{feature['id']}`) | {status} | {note} |")
    unmapped = sorted(t for t, r in results.items()
                      if not any(t in f.get("tests", []) for f in manifest["features"]))
    if unmapped:
        lines += ["", "## Tests not linked to a feature", ""] + [f"- `{t}`: {results[t]}" for t in unmapped]
    report = "\n".join(lines) + "\n"
    (run / "REPORT.md").write_text(report)
    if not only:
        (ROOT / "verification" / "LATEST.md").write_text(report)
    print(report)
    if problems:
        print("Problems:", *problems, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
