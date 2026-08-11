You are the sole implementation agent for this benchmark.
Read AGENTS.md and SPECIFICATION.md completely. You own the entire repository.

Work as a persistent goal executor even though this is one non-interactive Codex turn:
1. Inspect the repository and specification, then implement the complete project; do not stop after planning or after a partial subsystem.
2. Build with make clean all, run your own tests, then run ../grader.sh "$PWD".
3. If any build, test, or grader check fails, diagnose and repair it. Repeat that loop until every grader check passes.
4. Do not claim completion while any requirement or external grader check remains unmet.
5. Do not wait for user input, do not use other agents, do not modify files outside this repository, and do not create a git commit.

Your final response must state the exact build/test commands run and their outcomes. The durable result is the working repository, not prose.
