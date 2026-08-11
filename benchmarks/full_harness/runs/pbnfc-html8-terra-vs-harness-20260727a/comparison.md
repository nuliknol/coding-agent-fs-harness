# Benchmark comparison

| Competitor | Functional score | Wall seconds | Completed turns | Manager/worker switches | Input / cached input / output tokens | Estimated API USD | C/header LOC |
|---|---:|---:|---:|---:|---:|---:|---:|
| Single Terra High | 12/12 | 551 | 1 | 0 | 1370667 / 1317120 / 26662 | 0.863078 | 190 |
| Manager Terra High + Worker Luna High | 12/12 | 8055 | 81 | 81 | 41023421 / 39280640 / 363966 | 13.467938 | 3851 |

Functional score is the primary result. Token totals are provider-reported cumulative values, deduplicated by Codex thread; resumed-thread snapshots are not added repeatedly. `n/a` means the JSON events did not contain usage data.

Estimated API USD is calculated from `pricing.env`: uncached input × input rate + cached input × cached-input rate + output × output rate, divided by one million. For a ChatGPT-authenticated run, a populated value is an API-price equivalent based on the supplied rates, not an itemized charge; an empty pricing file produces `n/a`.

Detailed functional logs: [single](single/grader.out) and [manager/worker](manager-worker/grader.out).
