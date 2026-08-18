# Token usage anomaly resolution

Harness-Fix-Commit: 0843c48
Partial-Edit-Disposition: PRESERVE

## Cause

The first recovery replan still spent three publisher attempts guessing the
registered render-compile fixture source and crossed item 9 of the 8-item
investigation budget. It nevertheless published a validated revision-122 task;
the worker was unwound immediately when the durable anomaly interlock appeared,
and no worker source mutation was accepted.

## Corrective action

Harness 5.18.34 now injects deterministic validation-command ownership and the
first causal diagnostic into every recovery packet. The build broker resolves
`dpvis_render_compile_tests` directly to
`tests/render_compile/render_compile_tests.hip`, eliminating the filename-guess
publisher corrections. The already published task remains independently
validated; no token or action limit was raised.

## Safe continuation boundary

Preserve raw token history, the repository, accepted checkpoints, and the
published revision-122 assignment. Rotate the amplified thread, reset only the
orphaned worker transaction through normal restart recovery, and execute the
same first-unmet criterion with unchanged mutation authority.
