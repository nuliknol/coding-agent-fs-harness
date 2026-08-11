Resolved ADD-004:

- Closure workers now receive exactly `processed..snapshot`.
- Scan rounds use actual chart ranges, including safe empty ranges.
- `tasks=` now reports per-worker nonempty assignments rather than global generations.
- README updated accordingly.

Final verification:

```text
make clean all
../grader.sh "$PWD"   # SCORE 12/12
make test
```

Smoke stats confirm all eight workers have positive actual task counts.