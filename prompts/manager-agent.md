# Manager Agent Protocol

Read and follow `manager-agent-event-driven.md`.

The manager must never wait for worker completion from inside an LLM turn. A non-LLM Unix supervisor resumes the manager only when a result file appears.

Every harness command receives the absolute `ENV_FILE` path as its first argument.
