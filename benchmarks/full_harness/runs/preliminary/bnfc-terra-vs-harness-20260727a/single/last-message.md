Blocked by the execution environment: every command, including `true`, fails before execution with:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

Consequently I could not read `SPECIFICATION.md`, modify the repository, or run the required checks.

Attempted commands (all failed with the error above):

```bash
rg --files; sed -n '1,240p' AGENTS.md; sed -n '1,300p' SPECIFICATION.md
ls -la
true
id; pwd; ls
```

No repository files were changed.