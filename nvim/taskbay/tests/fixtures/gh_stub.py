#!/usr/bin/env python3
"""Offline stand-in for the GitHub CLI used by the taskbay GitHub e2e test.

It keeps issues in a JSON file and accepts only the commands, flags and JSON fields
that the real gh (2.105) accepts, so a call the real CLI would reject fails here too.
Every call is appended to calls.jsonl next to the state file.
"""
import json
import os
import sys

STATE_DIR = os.environ["GH_STUB_DIR"]
STATE = os.path.join(STATE_DIR, "issues.json")
REPO = "octo/project"
ISSUE_FIELDS = {
    "assignees", "author", "blockedBy", "blocking", "body", "closed", "closedAt",
    "closedByPullRequestsReferences", "comments", "createdAt", "id", "isPinned", "issueType", "labels",
    "milestone", "number", "parent", "projectCards", "projectItems", "reactionGroups", "state",
    "stateReason", "subIssues", "subIssuesSummary", "title", "updatedAt", "url",
}
REPO_FIELDS = {"nameWithOwner", "url", "defaultBranchRef", "name", "owner", "id"}
FLAGS = {  # value-taking flags per command; True marks a boolean flag
    ("repo", "view"): {"--json": False},
    ("issue", "list"): {"--repo": False, "--limit": False, "--json": False, "--search": False, "--state": False},
    ("issue", "view"): {"--repo": False, "--json": False},
    ("issue", "edit"): {
        "--repo": False, "--title": False, "--body": False, "--body-file": False, "--add-label": False,
        "--remove-label": False, "--add-assignee": False, "--remove-assignee": False, "--milestone": False,
        "--remove-milestone": True,
    },
    ("issue", "create"): {"--repo": False, "--title": False, "--body": False, "--body-file": False},
    ("issue", "close"): {"--repo": False, "--comment": False, "--reason": False},
    ("issue", "reopen"): {"--repo": False, "--comment": False},
}


def fail(message):
    sys.stderr.write(message + "\n")
    sys.exit(1)


def parse(command, args):
    allowed = FLAGS.get(command) or fail("unknown command: gh " + " ".join(command))
    flags, positional, i = {}, [], 0
    while i < len(args):
        arg = args[i]
        if arg.startswith("--"):
            if arg not in allowed:
                fail("unknown flag: " + arg)
            if allowed[arg]:
                flags.setdefault(arg, []).append(True)
                i += 1
                continue
            if i + 1 >= len(args):
                fail("flag needs an argument: " + arg)
            flags.setdefault(arg, []).append(args[i + 1])
            i += 2
        else:
            positional.append(arg)
            i += 1
    return flags, positional


def fields(flags, known):
    wanted = flags.get("--json", [""])[0].split(",")
    for name in wanted:
        if name not in known:
            fail('Unknown JSON field: "%s"' % name)
    return wanted


def one(flags, name):
    return flags.get(name, [None])[-1]


def main():
    args = sys.argv[1:]
    command, rest = tuple(args[:2]), args[2:]
    flags, positional = parse(command, rest)
    with open(os.path.join(STATE_DIR, "calls.jsonl"), "a") as log:
        log.write(json.dumps({"argv": args}) + "\n")
    state = json.load(open(STATE))
    repo_flag = one(flags, "--repo")
    if command[0] == "issue" and repo_flag not in (REPO, "github.com/" + REPO):
        fail("unknown repository: %s" % repo_flag)
    body = sys.stdin.read() if one(flags, "--body-file") == "-" else one(flags, "--body")
    issues = state["issues"]
    if command == ("repo", "view"):
        data = {"nameWithOwner": REPO, "url": "https://github.com/" + REPO, "defaultBranchRef": {"name": "main"}}
        print(json.dumps({k: data.get(k) for k in fields(flags, REPO_FIELDS)}))
    elif command == ("issue", "list"):
        wanted = fields(flags, ISSUE_FIELDS)
        found = [i for i in issues.values() if i["state"] == "OPEN"]
        query = one(flags, "--search")
        if query:
            found = [i for i in found if query.lower() in (i["title"] + i["body"]).lower()]
        found = found[: int(one(flags, "--limit") or 30)]
        print(json.dumps([{k: i.get(k) for k in wanted} for i in found]))
    else:
        if command == ("issue", "create"):
            number = max([int(n) for n in issues] or [0]) + 1
            issues[str(number)] = {
                "number": number, "title": one(flags, "--title"), "body": body or "", "state": "OPEN",
                "labels": [], "assignees": [], "milestone": None, "comments": [],
                "url": "https://github.com/%s/issues/%d" % (REPO, number),
            }
            json.dump(state, open(STATE, "w"))
            print(issues[str(number)]["url"])
            return
        if len(positional) != 1 or positional[0] not in issues:
            fail("issue not found: %s" % positional)
        issue = issues[positional[0]]
        if command == ("issue", "view"):
            print(json.dumps({k: issue.get(k) for k in fields(flags, ISSUE_FIELDS)}))
            return
        if command == ("issue", "edit"):
            if one(flags, "--title") is not None:
                issue["title"] = one(flags, "--title")
            if body is not None:
                issue["body"] = body
            names = [l["name"] for l in issue["labels"]]
            names = [n for n in names if n not in flags.get("--remove-label", [])] + flags.get("--add-label", [])
            issue["labels"] = [{"name": n} for n in names]
            logins = [a["login"] for a in issue["assignees"]]
            logins = [n for n in logins if n not in flags.get("--remove-assignee", [])] + flags.get("--add-assignee", [])
            issue["assignees"] = [{"login": n} for n in logins]
            if "--remove-milestone" in flags:
                issue["milestone"] = None
            elif one(flags, "--milestone"):
                issue["milestone"] = {"title": one(flags, "--milestone")}
        else:
            issue["state"] = "CLOSED" if command[1] == "close" else "OPEN"
        json.dump(state, open(STATE, "w"))
        print("https://github.com/%s/issues/%s" % (REPO, positional[0]))


main()
