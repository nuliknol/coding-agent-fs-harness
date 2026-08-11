# Benchmark comparison

| Competitor | Functional score | Wall seconds | Completed turns | Manager/worker switches | Input / cached input / output tokens | Estimated API USD | C/header LOC |
|---|---:|---:|---:|---:|---:|---:|---:|
| Single Terra High | 8/8 | 378 | 1 | 0 | 512180 / 482304 / 18187 | n/a | 109 |
| Manager Terra High + Worker Luna High | 1/8 | n/a | 5 | 6 | 2527208 / 2354688 / 39965 | n/a | 158 |

Functional score is the primary result. Token totals are provider-reported values only; `n/a` means the JSON events did not contain usage data.

Estimated API USD is calculated from `pricing.env`: uncached input × input rate + cached input × cached-input rate + output × output rate, divided by one million. This live trial uses ChatGPT authentication, so the field intentionally remains `n/a`; the actual charge is subscription credits/usage limits, not an itemized token bill.

Detailed functional logs: [single](single/grader.out) and [manager/worker](manager-worker/grader.out).
