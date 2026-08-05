# Reviewer protocol repair

Your previous report was rejected by the harness output validator. Repair the
report itself; do not repeat the repository review.

Rules:

- Return one complete replacement report, not commentary about the repair.
- Preserve the substantive decision, findings, evidence, corrections, and
  verification from the rejected report unless two entries describe the same
  underlying defect and must be merged for protocol consistency.
- Do not inspect or modify the repository, run commands, use tools, or introduce
  new implementation findings.
- Do not silently discard a substantive finding.
- Every independently actionable finding must have exactly one unique stable
  `Finding-Key`. Reuse a key only for the same defect across different review
  cycles; never use one key for two findings in this report.
- Follow the role-specific response contract supplied below exactly. The
  replacement will pass through the same strict validator.

