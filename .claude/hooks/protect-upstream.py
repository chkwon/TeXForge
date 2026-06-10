#!/usr/bin/env python3
# Claude Code PreToolUse hook (Bash matcher).
# Hard guard: never let gh/git modify the upstream TeXShop/TeXShop repo.
# All PRs, issues, and releases belong to the fork: chkwon/TeXForge.
# Exit 2 blocks the tool call; stderr is fed back to Claude.
import json
import re
import sys


def block(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return  # malformed input: don't block unrelated work

    cmd = (data.get("tool_input") or {}).get("command") or ""

    # 1) Never push to the upstream remote (its push URL is also disabled in
    #    .git/config, this is belt and braces). Tokens may not cross shell
    #    separators, redirections, or quotes, so prose in commit messages or
    #    PR bodies elsewhere in the command cannot false-positive this rule.
    tok = r"[^\s;&|()<>'\"]+"
    if re.search(r'(^|[;&|(\s])git([ \t]+%s)*?[ \t]+push([ \t]+%s)*?[ \t]+upstream([ \t;&|)]|$)'
                 % (tok, tok), cmd):
        block("BLOCKED by .claude/hooks/protect-upstream.py: 'git push ... upstream' "
              "targets TeXShop/TeXShop. Push to origin (chkwon/TeXForge) instead.")

    # 2) gh commands that mention the upstream repo: only a single read-only
    #    invocation (view/list/status/diff/checks) is allowed.
    gh_invocations = re.findall(r'(?:^|[;&|(\s])gh\s', cmd)
    if gh_invocations and re.search(r'TeXShop/TeXShop', cmd, re.IGNORECASE):
        readonly = (len(gh_invocations) == 1
                    and re.search(r'(?:^|[;&|(\s])gh\s+\w+\s+(view|list|status|diff|checks)\b', cmd))
        if not readonly:
            block("BLOCKED by .claude/hooks/protect-upstream.py: gh command targets the "
                  "upstream TeXShop/TeXShop repo. NEVER modify upstream; the only "
                  "writable repo is chkwon/TeXForge. (Single read-only gh commands - "
                  "view/list/status/diff/checks - are exempt.)")

    # 3) gh pr create must explicitly target the fork, so a default-repo
    #    misresolution can never route a PR to the upstream parent again.
    if re.search(r'(?:^|[;&|(\s])gh\s+pr\s+create\b', cmd):
        if not re.search(r'(?:--repo|-R)[=\s]+[\'"]?chkwon/TeXForge[\'"]?(\s|$)', cmd):
            block("BLOCKED by .claude/hooks/protect-upstream.py: 'gh pr create' must "
                  "explicitly pass --repo chkwon/TeXForge (PRs must never go to the "
                  "upstream TeXShop/TeXShop repo).")


if __name__ == "__main__":
    main()
