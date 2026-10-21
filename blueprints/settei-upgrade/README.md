# settei-upgrade

Version: `0.1.0`. Agent-guided Settei source migration, one edge per release window
requiring judgement. This blueprint applies no baseline modules and entails no other
blueprints. The first edge targets the upcoming shared 0.3.0.0 release.

## For consumers

Update every Settei dependency together and configure/build to refresh the resolved
Cabal plan, then install the published upgrade guidance and migrate:

```bash
seihou install https://github.com/shinzui/settei.git --module settei-upgrade
seihou agent --debug migrate settei-upgrade --from 0.2.0.0
seihou agent migrate settei-upgrade
```

On a first run, pass `--from 0.2.0.0` if no receipt records the earlier position.
Subsequent runs infer it from receipts; `--to` comes from the resolved-version probe.
Agent edits use the consumer's version control for recovery. Use a clean working tree.

## Declared edges

| From | To | Guidance |
| --- | --- | --- |
| 0.2.0.0 | 0.3.0.0 | Checked diagnostic dispatch, new error/mode constructors, validated JSON failures |

## Version probe

```bash
jq -r '."install-plan"[] | select(."pkg-name"=="settei") | ."pkg-version"' dist-newstyle/cache/plan.json 2>/dev/null | sort -u | tail -1 | grep .
```

This read-only command reports the resolved core version because all family packages
pin the core exactly. Without a configured plan or `jq`, the probe fails visibly;
supply `--to` explicitly instead. Seihou runs it from the consumer's project root.

## For maintainers

Every breaking release adds its edge in the same change that cuts the release. Decide
at every release whether an edge is needed and record the decision either way. Append
an edge rather than rewriting released history. Bump blueprint and registry versions,
update this table, validate and debug-preview the window, and ensure the blueprint
commit is pushed before tagging: consumers install from git.

```bash
seihou validate-blueprint blueprints/settei-upgrade --lint
seihou agent --debug migrate settei-upgrade --from 0.2.0.0 --to 0.3.0.0
```

For a working-tree preview expose this directory temporarily as a symlink at
`~/.config/seihou/modules/settei-upgrade`; remove that link after preview so it does
not shadow a later installed version. The reference file `files/checked-dispatch.md`
is mounted for each edge. Its public-module after example is the same as
[the compiled fixture](../../settei-optparse-applicative/test/compile-pass/CheckedDispatch.hs)
and the [CLI guide](../../docs/guides/cli-application.md#add-diagnostics-that-match-user-intent).
See the [release checklist](../../docs/release-checklist.md) and
[release workflow](../../agents/skills/release/SKILL.md) for the required gates.
