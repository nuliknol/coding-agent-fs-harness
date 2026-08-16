# Context Closure Baseline and Existing Boundary Inventory

Generated: 2026-08-16 UTC

This baseline is reproducible from durable harness records and does not invoke
an agent. Per-project regeneration uses:

```text
harness-context-baseline ENV_FILE
harness-context-closure-outliers ENV_FILE
harness-context-closure-predictions ENV_FILE
```

## Existing context and execution boundaries

- Context capsules are generated per v2 leaf under
  `control/context-capsules/` and embedded once in the worker prompt.
- Required symbols, allowed paths, obligation allocation, architecture node
  bindings, focused validation, and model route are manager-authored leaf
  metadata.
- `codex-exec-jsonl` records actions, command output, source-read bytes,
  repeated reads, changed paths, processed tokens, duration, and resource-fuse
  classification per invocation.
- `complexity-observations.tsv` joins declared complexity to worker behavior;
  `complexity-outcomes.tsv` joins manager acceptance/checkpoint/rejection.
- Context Closure adds immutable repository generation, closure item/edge and
  unresolved ledgers, graph cuts, worker usage comparison, and provider
  provenance without replaying transcript content.

## Historical pre-closure sample

The following projects represent a short completed experiment, a repeatedly
problematic project, and a deliberately long project. Numbers are direct sums
of `logs/complexity-observations.tsv` as of this baseline.

| Project | Episodes | Processed tokens | Agent actions | Command output bytes | Source-read bytes | Repeated reads | Changed files (episode sum) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `dpvis-w2-a1` | 5 | 1,986,305 | 61 | 218,089 | 202,545 | 0 | 4 |
| `compmod-wc-3` | 68 | 8,091,652 | 462 | 1,146,664 | 967,441 | 0 | 10 |
| `dplm-final-v2` | 63 | 12,633,476 | 602 | 2,618,154 | 2,515,795 | 0 | 10 |

Regeneration expression for one state directory:

```text
awk -F '\t' 'NR>1 {n++; tokens+=$11; actions+=$13; output+=$15;
  source+=$17; repeats+=$18; changed+=$19}
  END {print n,tokens,actions,output,source,repeats,changed}' \
  STATE/logs/complexity-observations.tsv
```

These are comparison inputs, not proof that closure reduces cost. Advisory
outcomes and the promotion report provide the post-change evidence.
