# Mandatory completion-progress audit

This scheduled audit is part of the normal manager review; do not perform a
separate implementation task or weaken the ordinary `ACCEPT`/`REVISE`
decision. Independently inspect the immutable specification, current source,
and current executable evidence. Do not estimate from worker reports, review
count, diff size, or token use.

After the ordinary manager decision and any required `ADD-NNN` records, append
exactly one block in this form. The expected requirement IDs are supplied below
this policy and every one must appear exactly once, in the given order.

```text
COMPLETION-AUDIT: BEGIN
Audit-Cycle: <manager cycle>
Coverage-Basis: REQUIREMENT-IDS
Requirements-Total: <number of expected IDs>
Verified-Complete: <count>
Implemented-Unverified: <count>
Remaining-Gap: <count>
Blocked: <count>
Verified-Percent: <floor(100 * verified / total)>
Claimed-Percent: <floor(100 * (verified + implemented-unverified) / total)>

REQUIREMENT: <exact ID>
Status: VERIFIED | IMPLEMENTED | GAP | BLOCKED
Evidence: <specific current source/runtime evidence>
Verification: <current command/result, or the exact missing verification>

COMPLETION-AUDIT-COMPLETE
```

`VERIFIED` requires current repository evidence and reproducible verification.
`IMPLEMENTED` means code exists but required verification is incomplete.
`GAP` means implementation is absent, partial, disconnected, or regressed.
`BLOCKED` means a concrete external dependency or mutually incompatible
requirement prevents repository-local completion. Do not classify uncertainty
or lack of review effort as `BLOCKED`.

If the expected list contains only `SPECIFICATION-WHOLE`, use
`Coverage-Basis: SPECIFICATION-WHOLE` and still emit its one record. This is an
all-or-nothing audit, so the dashboard will display its percentage as `N/A`.

An `ACCEPT` decision requires every status to be `VERIFIED`. A `REVISE`
decision requires at least one status other than `VERIFIED`.
