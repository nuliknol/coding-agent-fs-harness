#!/usr/bin/env bash

set -Eeuo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harness-architecture.sh"

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

validation_is_review_descriptor()
{
	case "$1" in
		FOCUSED:*|INCREMENTAL:*|CLEAN_GLOBAL:*) return 0 ;;
		*) return 1 ;;
	esac
}

validation_is_executable_command()
{
	local validation="$1"
	validation_is_review_descriptor "$validation" && return 1
	architecture_validation_is_command_shaped "$validation"
}

timestamp_utc()
{
	date -u '+%Y-%m-%dT%H:%M:%SZ'
}

timestamp_compact_utc()
{
	date -u '+%Y%m%dT%H%M%SZ'
}

epoch_now()
{
	date '+%s'
}

codex_provider_retry_kind()
{
	case "$1" in
		provider_quota_exhausted) printf 'quota\n' ;;
		provider_transient_error) printf 'transient\n' ;;
		*) return 1 ;;
	esac
}

codex_provider_retry_delay()
{
	case "$1" in
		provider_quota_exhausted) printf '%s\n' "$HARNESS_QUOTA_RETRY_SECONDS" ;;
		provider_transient_error) printf '%s\n' "$HARNESS_PROVIDER_RETRY_SECONDS" ;;
		*) return 1 ;;
	esac
}

codex_model_requires_narrow_prompt()
{
	[[ "$1" =~ (^|[-_:])terra($|[-_:]) || "$1" =~ gpt-5[.]6 ]]
}

resolve_from_env_dir()
{
	local path="$1"
	if [[ "$path" == /* ]]; then
		realpath -m "$path"
	else
		realpath -m "$HARNESS_ENV_DIR/$path"
	fi
}

resolve_command_path()
{
	local value="$1"
	if [[ "$value" == */* ]]; then
		resolve_from_env_dir "$value"
	else
		printf '%s\n' "$value"
	fi
}

prepend_harness_runtime_path()
{
	local prefix="$1"
	local entry
	local -a entries
	[[ -n "$prefix" ]] || return 0
	[[ "$prefix" != *$'\n'* && "$prefix" != *$'\r'* ]] ||
		die 'HARNESS_RUNTIME_PATH_PREFIX must be a single colon-separated line'
	IFS=: read -r -a entries <<< "$prefix"
	for entry in "${entries[@]}"; do
		[[ -n "$entry" ]] || die 'HARNESS_RUNTIME_PATH_PREFIX must not contain empty entries'
		[[ "$entry" == /* ]] || die "HARNESS_RUNTIME_PATH_PREFIX entries must be absolute: $entry"
		[[ -d "$entry" ]] || die "HARNESS_RUNTIME_PATH_PREFIX directory does not exist: $entry"
	done
	PATH="$prefix${PATH:+:$PATH}"
	export PATH
}

require_executable_runtime()
{
	local role="$1"
	local value="$2"
	local executable magic shebang interpreter spec first second runtime
	if [[ "$value" == */* ]]; then
		executable="$value"
		[[ -x "$executable" ]] || die "$role Codex executable not found: $executable"
	else
		executable="$(command -v "$value" 2>/dev/null || true)"
		[[ -n "$executable" ]] || die "$role Codex command not found: $value"
	fi

	# An executable script can pass -x while its shebang runtime is absent.
	# Validate that dependency before a supervisor advertises itself as healthy.
	magic="$(LC_ALL=C head -c 2 "$executable" 2>/dev/null || true)"
	[[ "$magic" == '#!' ]] || return 0
	IFS= read -r shebang < "$executable" || true
	shebang="${shebang#\#!}"
	read -r interpreter spec <<< "$shebang"
	[[ -n "$interpreter" ]] || die "$role Codex executable has an invalid shebang: $executable"
	if [[ "${interpreter##*/}" == env ]]; then
		read -r first second _ <<< "$spec"
		if [[ "$first" == -S ]]; then
			runtime="$second"
		else
			runtime="$first"
		fi
		[[ -n "$runtime" ]] || die "$role Codex executable has an invalid env shebang: $executable"
		command -v "$runtime" >/dev/null 2>&1 ||
			die "$role Codex runtime '$runtime' is not available in PATH for $executable; set HARNESS_RUNTIME_PATH_PREFIX in $HARNESS_ENV_FILE"
	else
		[[ -x "$interpreter" ]] ||
			die "$role Codex shebang runtime is not executable: $interpreter"
	fi
}

load_harness_env()
{
	[[ $# -eq 1 ]] || die 'load_harness_env requires exactly one ENV_FILE argument'
	local input="$1"
	[[ -f "$input" ]] || die "environment file does not exist: $input"

	local canonical_file canonical_dir
	canonical_file="$(realpath "$input")"
	canonical_dir="$(dirname "$canonical_file")"

	local owner mode_octal mode
	owner="$(stat -c '%u' "$canonical_file")"
	mode_octal="$(stat -c '%a' "$canonical_file")"
	mode=$((8#$mode_octal))
	(( owner == UID || owner == 0 )) || die "environment file must be owned by UID $UID or root: $canonical_file"
	(( (mode & 8#022) == 0 )) || die "environment file must not be group/world writable: $canonical_file"

	unset PROJECT REPOSITORY SPECIFICATION HARNESS_MODE harness_mode HARNESS_HOME HARNESS_BIN HARNESS_ROOT PROJECT_TMP_DIR
	unset HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY
	unset HARNESS_RUNTIME_PATH_PREFIX
	unset HARNESS_BOOT_RECOVERY
	unset HARNESS_MAX_IDENTICAL_BLOCKERS HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS HARNESS_MAX_IDENTICAL_RESOURCE_FUSES
	unset HARNESS_MAX_ROOT_ATTEMPTS HARNESS_MAX_ZERO_GAIN_WINDOW
	unset HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION
	unset HARNESS_MAX_TOTAL_ROOT_REVIEWS HARNESS_MAX_TOTAL_ROOT_REPLANS
	unset HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION
	unset HARNESS_MAX_ROOT_CHILD_CRITERIA HARNESS_MAX_CRITERION_DEPTH
	unset HARNESS_MAX_ROOT_LIFETIME_SECONDS HARNESS_MAX_ROOT_PROCESSED_TOKENS
	unset HARNESS_AUTO_REPLAN_ENABLED HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN
	unset HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION
	unset HARNESS_REUSE_WORKER_THREADS HARNESS_WORKER_THREAD_MAX_REJECTIONS
	unset HARNESS_CLOSURE_MODE_ENABLED HARNESS_CLOSURE_MODE_MIN_PROGRESS
	unset HARNESS_CLOSURE_MODE_MAX_FIXES HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS
	unset HARNESS_WORKER_GOAL_MODE HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS
	unset HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS HARNESS_GOAL_PROCESS_MAX_FIXES
	unset HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS
	unset HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED
	unset HARNESS_DECOMPOSITION_V2 HARNESS_DECOMPOSITION_CRITIC_ENABLED
	unset HARNESS_SPECIFICATION_REVIEW_ENABLED
	unset HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS HARNESS_START_MAX_AGENT_INVOCATIONS
	unset HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD
	unset HARNESS_DOMAIN_PROFILES
	unset HARNESS_MODEL_POLICY HARNESS_ESCALATION_POLICY
	unset HARNESS_REPOSITORY_INDEX_MODE HARNESS_REPOSITORY_OVERLAY_MODE HARNESS_CONTEXT_CLOSURE_MODE
	unset HARNESS_REPOSITORY_INDEX_ROOT HARNESS_COMPILE_COMMANDS
	unset HARNESS_SCIP_CLANG_BIN HARNESS_SCIP_BIN HARNESS_SCIP_IMPORTER_BIN HARNESS_JOERN_BIN HARNESS_JOERN_ENABLED
	unset HARNESS_JOERN_ANALYSIS_CLASSES HARNESS_JOERN_SOURCE_ROOT HARNESS_JOERN_EXCLUDE_REGEX HARNESS_JOERN_TIMEOUT_SECONDS HARNESS_JOERN_EXECUTION_MODE
	unset HARNESS_JOERN_MAX_HEAP_MB HARNESS_JOERN_MAX_CPUS HARNESS_JOERN_NICE_LEVEL
	unset HARNESS_RECOLL_BIN HARNESS_RECOLL_ENABLED HARNESS_REPOSITORY_INDEX_RETENTION
	unset HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES
	unset HARNESS_SCIP_CLANG_JOBS HARNESS_CONTEXT_CLOSURE_MAX_BYTES HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES
	unset HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS HARNESS_CONTEXT_CLOSURE_MAX_MODULES
	unset HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES
	unset HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS HARNESS_CONTEXT_CLOSURE_MAX_TESTS
	unset HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS
	unset HARNESS_CONTEXT_EXPANSION_MAX_BYTES HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF
	unset HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS
	unset HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT
	unset HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT
	unset HARNESS_MAX_LUNA_STRATEGY_FAILURES HARNESS_MAX_LUNA_ALLOWED_PATHS HARNESS_MIN_LUNA_NODE_PERCENT
	unset HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES
	unset HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS HARNESS_MAX_LUNA_FAILURE_PATHS
	unset HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES
	unset HARNESS_MAX_LUNA_VALIDATION_SURFACES HARNESS_MAX_LUNA_IMPLEMENTATION_FILES
	unset HARNESS_MAX_LUNA_REQUIRED_SYMBOLS HARNESS_MAX_LUNA_PREDICTED_ACTIONS
	unset HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS
	unset HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS HARNESS_MAX_LUNA_COMPLEXITY_SCORE
	unset HARNESS_MAX_LUNA_RISK_DOMAINS HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT
	unset HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES
	unset HARNESS_VALIDATION_OUTPUT_MAX_LINES HARNESS_VALIDATION_OUTPUT_MAX_BYTES
	unset HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES
	unset HARNESS_MIN_LUNA_CODING_NODE_PERCENT HARNESS_ARCHITECTURE_GUARDS
	unset HARNESS_PREFERRED_WORKER_ROUTE HARNESS_AGENT_COMMITS_ENABLED
	unset HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS
	unset HARNESS_AGENT_MIN_INTERVAL_SECONDS
	unset HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION HARNESS_AGENT_ITEM_HEADROOM HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION
	unset HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS
	unset HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION
	unset HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND
	unset HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION
	unset HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS
	unset HARNESS_IRREGULARITY_DETECTION_ENABLED HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT
	unset HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT
	unset HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET
	unset HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS
	unset HARNESS_MAX_STATE_OSCILLATIONS HARNESS_MAX_PATCH_CHURN_ROUNDS
	unset HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION
	unset HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION
	unset HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	unset HARNESS_CODEX_WALL_TIMEOUT_SECONDS HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_KILL_GRACE_SECONDS
	unset MANAGER_FALLBACK_MODEL WORKER_FALLBACK_MODEL ORACLE_FALLBACK_MODEL
	unset DECOMPOSITION_MODEL DECOMPOSITION_REASONING_EFFORT
	unset ORACLE_MODEL ORACLE_REASONING_EFFORT ORACLE_SANDBOX ORACLE_CODEX_BIN ORACLE_CODEX_HOME ORACLE_CODEX_EXTRA_ARGS ORACLE_ENABLED MAX_ORACLE_RUNS
	unset HARNESS_MANAGER_INVOKER HARNESS_MANAGER_PLAN_INVOKER HARNESS_MANAGER_REPLAN_INVOKER
	unset HARNESS_WORKER_INVOKER HARNESS_ORACLE_INVOKER
	unset CODEX_BIN CODEX_HOME
	unset CODEX_EXTRA_ARGS
	unset MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	unset MANAGER_CODEX_EXTRA_ARGS
	unset WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	unset WORKER_CODEX_EXTRA_ARGS
	unset LUNA_WORKER_MODEL LUNA_WORKER_REASONING_EFFORT
	unset TERRA_WORKER_MODEL TERRA_WORKER_REASONING_EFFORT
	unset WORKER_HEARTBEAT_SECONDS

	# The environment file is trusted Bash input.
	# shellcheck disable=SC1090
	source "$canonical_file"
	HARNESS_ENV_FILE="$canonical_file"
	HARNESS_ENV_DIR="$canonical_dir"
	HARNESS_MODE="${HARNESS_MODE:-${harness_mode:-full}}"
	[[ "$HARNESS_MODE" == full ]] ||
		die "full-mode command received HARNESS_MODE=$HARNESS_MODE; use a shared top-level entry point"
	HARNESS_RUNTIME_PATH_PREFIX="${HARNESS_RUNTIME_PATH_PREFIX:-}"
	HARNESS_BOOT_RECOVERY="${HARNESS_BOOT_RECOVERY:-0}"
	prepend_harness_runtime_path "$HARNESS_RUNTIME_PATH_PREFIX"

	[[ -n "${PROJECT:-}" ]] || die "PROJECT is not set in $HARNESS_ENV_FILE"
	[[ -n "${REPOSITORY:-}" ]] || die "REPOSITORY is not set in $HARNESS_ENV_FILE"
	[[ -n "${HARNESS_HOME:-}" ]] || die "HARNESS_HOME is not set in $HARNESS_ENV_FILE"

	HARNESS_HOME="$(resolve_from_env_dir "$HARNESS_HOME")"
	HARNESS_BIN="${HARNESS_BIN:-$HARNESS_HOME/bin}"
	HARNESS_BIN="$(resolve_from_env_dir "$HARNESS_BIN")"
	HARNESS_ROOT="${HARNESS_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/coding-harness-${UID}}"
	HARNESS_ROOT="$(resolve_from_env_dir "$HARNESS_ROOT")"
	REPOSITORY="$(resolve_from_env_dir "$REPOSITORY")"
	PROJECT_TMP_DIR="/tmp/$PROJECT"

	SPECIFICATION="${SPECIFICATION:-}"
	if [[ -n "$SPECIFICATION" ]]; then
		SPECIFICATION="$(resolve_from_env_dir "$SPECIFICATION")"
	fi

	HARNESS_POLL_SECONDS="${HARNESS_POLL_SECONDS:-2}"
	HARNESS_WAIT_SECONDS="${HARNESS_WAIT_SECONDS:-300}"
	HARNESS_STALE_SECONDS="${HARNESS_STALE_SECONDS:-900}"
	HARNESS_USE_INOTIFY="${HARNESS_USE_INOTIFY:-1}"
	# Revisions remain automatic by default. Projects may explicitly opt into a
	# deterministic zero-progress circuit breaker with a positive threshold.
	HARNESS_MAX_IDENTICAL_BLOCKERS="${HARNESS_MAX_IDENTICAL_BLOCKERS:-0}"
	# Manager remediation is already the escalation path for an ordinary local
	# blocker. Repeating the same blocker inside that path must stop for an
	# architecture reassessment instead of recursively launching more Terra
	# remediation leaves.
	HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS="${HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS:-3}"
	HARNESS_MAX_IDENTICAL_RESOURCE_FUSES="${HARNESS_MAX_IDENTICAL_RESOURCE_FUSES:-3}"
	# A changing failure fingerprint must not permit an oversized root to run
	# forever. These convergence guards pause the root in NEEDS_REPLAN while
	# preserving every verified checkpoint and the live workspace.
	HARNESS_MAX_ROOT_ATTEMPTS="${HARNESS_MAX_ROOT_ATTEMPTS:-12}"
	HARNESS_MAX_ZERO_GAIN_WINDOW="${HARNESS_MAX_ZERO_GAIN_WINDOW:-3}"
	HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION="${HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION:-4}"
	# These monotonic plan-item budgets never reset after a checkpoint or an
	# automatic replan. They bound decomposition treadmills that can otherwise
	# manufacture local evidence indefinitely without completing the root.
	HARNESS_MAX_TOTAL_ROOT_REVIEWS="${HARNESS_MAX_TOTAL_ROOT_REVIEWS:-24}"
	HARNESS_MAX_TOTAL_ROOT_REPLANS="${HARNESS_MAX_TOTAL_ROOT_REPLANS:-8}"
	# This plan-level budget is deliberately not reset by an automatic replan,
	# a diagnostic checkpoint, a source edit, or a changing blocker string. It
	# resets only when a declared root criterion is durably checkpointed.
	HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION="${HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION:-10}"
	HARNESS_MAX_ROOT_CHILD_CRITERIA="${HARNESS_MAX_ROOT_CHILD_CRITERIA:-32}"
	HARNESS_MAX_CRITERION_DEPTH="${HARNESS_MAX_CRITERION_DEPTH:-8}"
	HARNESS_MAX_ROOT_LIFETIME_SECONDS="${HARNESS_MAX_ROOT_LIFETIME_SECONDS:-21600}"
	HARNESS_MAX_ROOT_PROCESSED_TOKENS="${HARNESS_MAX_ROOT_PROCESSED_TOKENS:-100000000}"
	# A convergence pause is normally recovered without an operator. The
	# recovery turn resumes the persistent manager, starts a fresh worker
	# strategy, may install a durable criterion decomposition for a legacy root,
	# and must publish a
	# materially different first-unmet-criterion continuation. A newly verified
	# checkpoint or criterion resets the escalation budget; percentage progress
	# is deliberately not used as a proxy for durable gain.
	HARNESS_AUTO_REPLAN_ENABLED="${HARNESS_AUTO_REPLAN_ENABLED:-1}"
	HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN="${HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN:-${HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION:-1}}"
	# Backwards-compatible alias for existing environment files. New code and
	# snapshots use the verified-gain name.
	HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION="$HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN"
	# A rejected continuation normally resumes the same root-scoped Codex
	# worker thread. Rotate periodically so one stale strategy or an overgrown
	# context cannot live for the entire root task.
	HARNESS_REUSE_WORKER_THREADS="${HARNESS_REUSE_WORKER_THREADS:-1}"
	HARNESS_WORKER_THREAD_MAX_REJECTIONS="${HARNESS_WORKER_THREAD_MAX_REJECTIONS:-8}"
	# Near completion, let one bounded worker turn diagnose, correct, rebuild,
	# and retry the same focused acceptance gate instead of forcing one revision
	# for every newly exposed failure.
	HARNESS_CLOSURE_MODE_ENABLED="${HARNESS_CLOSURE_MODE_ENABLED:-1}"
	HARNESS_CLOSURE_MODE_MIN_PROGRESS="${HARNESS_CLOSURE_MODE_MIN_PROGRESS:-95}"
	HARNESS_CLOSURE_MODE_MAX_FIXES="${HARNESS_CLOSURE_MODE_MAX_FIXES:-2}"
	HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS="${HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS:-3}"
	# Leaf-goal execution keeps one worker on one independently verifiable
	# criterion across several Codex turns. Internal CONTINUE receipts never
	# enter the manager result mailbox; only terminal goal outcomes do. New
	# assignments use this lifecycle by default; set 0 explicitly at a clean
	# task boundary to retain the legacy one-turn worker.
	HARNESS_WORKER_GOAL_MODE="${HARNESS_WORKER_GOAL_MODE:-1}"
	HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS="${HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS:-3}"
	HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS="${HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS:-8}"
	HARNESS_GOAL_PROCESS_MAX_FIXES="${HARNESS_GOAL_PROCESS_MAX_FIXES:-3}"
	HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS="${HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS:-4}"
	# A worker CONTINUE receipt closes one semantic episode. A compact, fresh
	# manager turn must confirm that the proposed next action still belongs to
	# the same criterion and authority before another fresh worker episode can
	# begin. This prevents an initially bounded leaf from silently turning into
	# an unbounded investigation while leaving implementation tactics to Codex.
	HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED="${HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED:-1}"
	# Version-two decomposition is opt-in for old environment files so active
	# projects keep their immutable v1 plan. New example configurations enable
	# it. V2 installs a validated dependency DAG, a pre-execution critic gate,
	# Luna-ready leaf contracts, context capsules, and per-leaf model routing.
	HARNESS_DECOMPOSITION_V2="${HARNESS_DECOMPOSITION_V2:-0}"
	HARNESS_DECOMPOSITION_CRITIC_ENABLED="${HARNESS_DECOMPOSITION_CRITIC_ENABLED:-$HARNESS_DECOMPOSITION_V2}"
	# Fresh v2 projects must establish that their governing specification is
	# complete enough to accept before the execution DAG is registered. Existing
	# plans are already across that boundary and remain migration-compatible.
	HARNESS_SPECIFICATION_REVIEW_ENABLED="${HARNESS_SPECIFICATION_REVIEW_ENABLED:-$HARNESS_DECOMPOSITION_V2}"
	# Specification normalization is a compiler pass, not an open-ended agent
	# strategy. Permit one automatic repair and bound the complete startup
	# transaction so a malformed source or non-converging critic cannot consume
	# an unlimited number of manager turns.
	HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS="${HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS:-1}"
	# Specification review, architecture fit, initial Sol decomposition, up to
	# three bounded complexity-split passes, architecture binding, and bootstrap
	# can legitimately require eight turns. Ten leaves two schema-repair slots
	# while the per-phase convergence guards still prevent loops.
	HARNESS_START_MAX_AGENT_INVOCATIONS="${HARNESS_START_MAX_AGENT_INVOCATIONS:-10}"
	# Above this normalized-IR size, a relation/cycle repair is itself a global
	# decomposition operation. It receives the global Sol allowance once while
	# retaining a repository-free context capsule.
	HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD="${HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD:-96}"
	# Optional, explicitly selected domain-theory profiles contribute reusable
	# human-owned invariants to specification normalization. An empty list adds
	# no product semantics. Names resolve first from the repository and then from
	# the harness installation.
	HARNESS_DOMAIN_PROFILES="${HARNESS_DOMAIN_PROFILES:-}"
	# Model policy is independent from the leaf-route preference. The legacy
	# policy preserves existing deployments; luna_only makes every semantic role
	# use the configured Luna model and forbids stronger-model escalation.
	HARNESS_MODEL_POLICY="${HARNESS_MODEL_POLICY:-legacy}"
	if [[ -z "${HARNESS_ESCALATION_POLICY+x}" ]]; then
		if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			HARNESS_ESCALATION_POLICY=decompose
		else
			HARNESS_ESCALATION_POLICY=legacy
		fi
	fi
	# Repository intelligence is initially inert. Advisory and required modes are
	# introduced behind explicit configuration so installing a newer harness
	# cannot mutate or block an existing project.
	HARNESS_REPOSITORY_INDEX_MODE="${HARNESS_REPOSITORY_INDEX_MODE:-off}"
	if [[ -z "${HARNESS_REPOSITORY_OVERLAY_MODE+x}" ]]; then
		if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			HARNESS_REPOSITORY_OVERLAY_MODE=tracked
		else
			HARNESS_REPOSITORY_OVERLAY_MODE=off
		fi
	fi
	HARNESS_CONTEXT_CLOSURE_MODE="${HARNESS_CONTEXT_CLOSURE_MODE:-off}"
	HARNESS_REPOSITORY_INDEX_ROOT="${HARNESS_REPOSITORY_INDEX_ROOT:-$HARNESS_ROOT/repository-indexes}"
	if [[ "$HARNESS_REPOSITORY_INDEX_ROOT" != /* ]]; then
		HARNESS_REPOSITORY_INDEX_ROOT="$(resolve_from_env_dir "$HARNESS_REPOSITORY_INDEX_ROOT")"
	else
		HARNESS_REPOSITORY_INDEX_ROOT="$(realpath -m "$HARNESS_REPOSITORY_INDEX_ROOT")"
	fi
	HARNESS_COMPILE_COMMANDS="${HARNESS_COMPILE_COMMANDS:-}"
	if [[ -n "$HARNESS_COMPILE_COMMANDS" && "$HARNESS_COMPILE_COMMANDS" != /* ]]; then
		HARNESS_COMPILE_COMMANDS="$(realpath -m "$REPOSITORY/$HARNESS_COMPILE_COMMANDS")"
	elif [[ -n "$HARNESS_COMPILE_COMMANDS" ]]; then
		HARNESS_COMPILE_COMMANDS="$(realpath -m "$HARNESS_COMPILE_COMMANDS")"
	fi
	HARNESS_SCIP_CLANG_BIN="${HARNESS_SCIP_CLANG_BIN:-scip-clang}"
	HARNESS_SCIP_BIN="${HARNESS_SCIP_BIN:-scip}"
	HARNESS_SCIP_IMPORTER_BIN="${HARNESS_SCIP_IMPORTER_BIN:-$HARNESS_HOME/libexec/harness-scip-importer}"
	HARNESS_JOERN_BIN="${HARNESS_JOERN_BIN:-joern}"
	HARNESS_JOERN_ENABLED="${HARNESS_JOERN_ENABLED:-0}"
	if [[ -z "${HARNESS_JOERN_EXECUTION_MODE+x}" ]]; then
		if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			HARNESS_JOERN_EXECUTION_MODE=on_demand
		else
			HARNESS_JOERN_EXECUTION_MODE=eager
		fi
	fi
	HARNESS_JOERN_ANALYSIS_CLASSES="${HARNESS_JOERN_ANALYSIS_CLASSES:-call,data-flow,control-flow,mutation}"
	HARNESS_JOERN_SOURCE_ROOT="${HARNESS_JOERN_SOURCE_ROOT:-.}"
	HARNESS_JOERN_EXCLUDE_REGEX="${HARNESS_JOERN_EXCLUDE_REGEX:-}"
	HARNESS_JOERN_TIMEOUT_SECONDS="${HARNESS_JOERN_TIMEOUT_SECONDS:-900}"
	# Repository refreshes from different harness projects share one Joern
	# admission lock.  Bound each admitted JVM as a second line of defence so a
	# large CPG cannot take every core or let the JVM choose an unbounded heap.
	if [[ -z "${HARNESS_JOERN_MAX_HEAP_MB+x}" ]]; then
		[[ "$HARNESS_MODEL_POLICY" == luna_only ]] && HARNESS_JOERN_MAX_HEAP_MB=4096 || HARNESS_JOERN_MAX_HEAP_MB=12288
	fi
	if [[ -z "${HARNESS_JOERN_MAX_CPUS+x}" ]]; then
		[[ "$HARNESS_MODEL_POLICY" == luna_only ]] && HARNESS_JOERN_MAX_CPUS=1 || HARNESS_JOERN_MAX_CPUS=2
	fi
	HARNESS_JOERN_NICE_LEVEL="${HARNESS_JOERN_NICE_LEVEL:-10}"
	HARNESS_RECOLL_BIN="${HARNESS_RECOLL_BIN:-recollq}"
	HARNESS_SCIP_CLANG_BIN="$(resolve_command_path "$HARNESS_SCIP_CLANG_BIN")"
	HARNESS_SCIP_BIN="$(resolve_command_path "$HARNESS_SCIP_BIN")"
	HARNESS_SCIP_IMPORTER_BIN="$(resolve_command_path "$HARNESS_SCIP_IMPORTER_BIN")"
	HARNESS_JOERN_BIN="$(resolve_command_path "$HARNESS_JOERN_BIN")"
	HARNESS_RECOLL_ENABLED="${HARNESS_RECOLL_ENABLED:-0}"
	if (( HARNESS_RECOLL_ENABLED == 1 )); then
		HARNESS_RECOLL_BIN="$(resolve_command_path "$HARNESS_RECOLL_BIN")"
	fi
	HARNESS_REPOSITORY_INDEX_RETENTION="${HARNESS_REPOSITORY_INDEX_RETENTION:-3}"
	HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES="${HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES:-5}"
	HARNESS_SCIP_CLANG_JOBS="${HARNESS_SCIP_CLANG_JOBS:-1}"
	HARNESS_CONTEXT_CLOSURE_MAX_BYTES="${HARNESS_CONTEXT_CLOSURE_MAX_BYTES:-32768}"
	# Sol architecture review consumes one compiled global evidence surface.
	# Keep it below the per-command transcript fuse even though it is embedded
	# directly in the prompt and never emitted by an agent shell command.
	HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES="${HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES:-32768}"
	HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES="${HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES:-65536}"
	HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES="${HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES:-98304}"
	HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS="${HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS:-64}"
	HARNESS_CONTEXT_CLOSURE_MAX_MODULES="${HARNESS_CONTEXT_CLOSURE_MAX_MODULES:-4}"
	HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES="${HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES:-2}"
	HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS="${HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS:-16}"
	HARNESS_CONTEXT_CLOSURE_MAX_TESTS="${HARNESS_CONTEXT_CLOSURE_MAX_TESTS:-8}"
	HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS="${HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS:-4}"
	HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS="${HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS:-250000}"
	HARNESS_CONTEXT_EXPANSION_MAX_BYTES="${HARNESS_CONTEXT_EXPANSION_MAX_BYTES:-8192}"
	HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF="${HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF:-2}"
	# A patch-only Luna receives compact typed diagnostics and may repair the
	# same bounded patch transaction. Repeated identical failure sets terminate
	# early; this value is a hard ceiling, not an unconditional retry count.
	HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS="${HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS:-3}"
	HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES="${HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES:-20}"
	HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT="${HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT:-95}"
	HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT="${HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT:-90}"
	HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT="${HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT:-5}"
	HARNESS_MAX_LUNA_STRATEGY_FAILURES="${HARNESS_MAX_LUNA_STRATEGY_FAILURES:-3}"
	# Allowed-Scope includes source, build registration, fixtures, and focused
	# validation paths. Keep the implementation-file budget at five, but permit
	# a bounded capsule to name a few related non-implementation paths.
	HARNESS_MAX_LUNA_ALLOWED_PATHS="${HARNESS_MAX_LUNA_ALLOWED_PATHS:-8}"
	# Cheap-worker leaves must be semantically bounded as well as path-bounded.
	# A large obligation fan-in belongs in a decision/integration node or must be
	# split before a Luna implementation leaf can be registered.
	HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF="${HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF:-2}"
	HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES="${HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES:-32768}"
	# The complexity contract is deliberately multidimensional. A cheap-worker
	# leaf must satisfy every limit; a low aggregate score cannot hide one hard
	# concurrency, ownership, failure-atomicity, or context dimension. Sol emits
	# the declared vector, while deterministic obligation/path/symbol/risk floors
	# prevent optimistic labels from making a broad node executable.
	HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS="${HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS:-1}"
	HARNESS_MAX_LUNA_FAILURE_PATHS="${HARNESS_MAX_LUNA_FAILURE_PATHS:-2}"
	HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS="${HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS:-1}"
	HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES="${HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES:-1}"
	HARNESS_MAX_LUNA_VALIDATION_SURFACES="${HARNESS_MAX_LUNA_VALIDATION_SURFACES:-1}"
	HARNESS_MAX_LUNA_IMPLEMENTATION_FILES="${HARNESS_MAX_LUNA_IMPLEMENTATION_FILES:-3}"
	HARNESS_MAX_LUNA_REQUIRED_SYMBOLS="${HARNESS_MAX_LUNA_REQUIRED_SYMBOLS:-3}"
	HARNESS_MAX_LUNA_PREDICTED_ACTIONS="${HARNESS_MAX_LUNA_PREDICTED_ACTIONS:-8}"
	# A source-changing episode needs enough room to inspect its bounded context,
	# edit, validate, commit, and publish a result. A smaller prediction is an
	# incomplete execution plan, not a useful circuit breaker.
	HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS="${HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS:-6}"
	HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS="${HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS:-250000}"
	HARNESS_MAX_LUNA_COMPLEXITY_SCORE="${HARNESS_MAX_LUNA_COMPLEXITY_SCORE:-24}"
	HARNESS_MAX_LUNA_RISK_DOMAINS="${HARNESS_MAX_LUNA_RISK_DOMAINS:-2}"
	HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT="${HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT:-10000}"
	HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES="${HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES:-10}"
	HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES="${HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES:-3}"
	# Build and test commands retain their complete output on disk. Only a
	# bounded diagnostic summary is allowed back into an agent transcript.
	HARNESS_VALIDATION_OUTPUT_MAX_LINES="${HARNESS_VALIDATION_OUTPUT_MAX_LINES:-200}"
	HARNESS_VALIDATION_OUTPUT_MAX_BYTES="${HARNESS_VALIDATION_OUTPUT_MAX_BYTES:-32768}"
	# One verbose command can poison an otherwise bounded context before the
	# aggregate token estimator sees the next reasoning item. Stop that episode
	# as soon as a completed command crosses this byte boundary.
	HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES="${HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES:-32768}"
	# Manager turns consume a generated review/planning capsule that can exceed
	# one worker-sized source excerpt without representing runaway build output.
	# Worker commands retain the tighter generic limit.
	HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES="${HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES:-65536}"
	# Fresh v2 plans must put most independently executable nodes on the cheap
	# worker route. Existing immutable DAGs are not rewritten by this setting.
	HARNESS_MIN_LUNA_NODE_PERCENT="${HARNESS_MIN_LUNA_NODE_PERCENT:-80}"
	HARNESS_MIN_LUNA_CODING_NODE_PERCENT="${HARNESS_MIN_LUNA_CODING_NODE_PERCENT:-$HARNESS_MIN_LUNA_NODE_PERCENT}"
	# New Full-v2 projects use architecture guards by default. Existing plans
	# created before the sidecars existed remain compatible and default off;
	# setting the variable explicitly always wins.
	if [[ -z "${HARNESS_ARCHITECTURE_GUARDS+x}" ]]; then
		if (( HARNESS_DECOMPOSITION_V2 == 1 )) && {
			[[ ! -f "$HARNESS_ROOT/projects/$PROJECT/control/project-plan.tsv" ]] ||
			[[ -f "$HARNESS_ROOT/projects/$PROJECT/control/architecture/invariants.tsv" ]]
		}; then
			HARNESS_ARCHITECTURE_GUARDS=1
		else
			HARNESS_ARCHITECTURE_GUARDS=0
		fi
	fi
	# V2 uses Terra for unresolved decisions and Luna for bounded coding.  This
	# preference also lets old immutable Terra-heavy DAG nodes be reclassified at
	# publication time when the manager can prove a Luna-ready execution leaf.
	HARNESS_PREFERRED_WORKER_ROUTE="${HARNESS_PREFERRED_WORKER_ROUTE:-LUNA}"
	if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
		HARNESS_PREFERRED_WORKER_ROUTE=LUNA
	fi
	# Implementation agents publish focused source-only commits by default.
	HARNESS_AGENT_COMMITS_ENABLED="${HARNESS_AGENT_COMMITS_ENABLED:-1}"
	# Provider-side failures retry forever. Short transient failures use a
	# one-minute cadence; account usage-window exhaustion reports and probes every
	# five minutes until Codex confirms quota is available again.
	HARNESS_PROVIDER_RETRY_SECONDS="${HARNESS_PROVIDER_RETRY_SECONDS:-${HARNESS_CAPACITY_RETRY_SECONDS:-60}}"
	HARNESS_QUOTA_RETRY_SECONDS="${HARNESS_QUOTA_RETRY_SECONDS:-300}"
	# Rate-limit every provider-backed agent launch through one project-wide
	# clock. This bounds token loss when any manager, worker, or oracle event
	# accidentally livelocks while preserving independent project parallelism.
	HARNESS_AGENT_MIN_INTERVAL_SECONDS="${HARNESS_AGENT_MIN_INTERVAL_SECONDS:-60}"
	# A Codex process can perform many internal model/tool steps before returning
	# usage accounting. Bound that live stream as well as its final token delta.
	HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION="${HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION:-80}"
	# Sol predicts semantic work actions, while the Codex JSONL stream also
	# counts planning/finalization items.  A two-item allowance repeatedly cut
	# off otherwise bounded edit+validation turns at item nine.  Keep explicit
	# headroom below the global hard ceiling instead of turning a p95 estimate
	# into a brittle exact limit.
	# A source-changing turn has protocol items for initial planning, each
	# semantic action, tool-result transitions, and finalization. Production
	# traces show the final result starts on semantic-actions + 7; +6 stops the
	# turn one JSONL item before it can publish the result.
	HARNESS_AGENT_ITEM_HEADROOM="${HARNESS_AGENT_ITEM_HEADROOM:-7}"
	# Reviews are bounded verification transactions, not exploratory coding.
	HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION="${HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION:-14}"
	# Replanning is also a bounded planning transaction.  A failed assignment
	# publication must not turn into an open-ended prompt-debugging session.
	HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION="${HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION:-14}"
	HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS="${HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS:-3}"
	HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION="${HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION:-500000}"
	# Model-reported input includes fixed system/tool framing that the semantic
	# leaf p95 does not predict exactly. Permit a small bounded margin around the
	# measured p95 while retaining the project-wide 500K hard fuse.
	# A predicted p95 is a planning estimate, not a hard maximum. Keep a bounded
	# tail allowance below the independent absolute fuse so ordinary fixed
	# prompt/tool framing does not pause successful, compact leaf episodes.
	HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT="${HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT:-50}"
	# Provider usage is cumulative across the model/tool rounds inside one
	# invocation. Account for fixed system/tool framing per round in addition to
	# the generated prompt; otherwise a tiny semantic prediction can become an
	# unrealistically low runtime fuse before useful verification completes.
	HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND="${HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND:-20000}"
	# Codex reports authoritative usage only when a turn ends. Estimate live
	# context amplification from prompt/transcript size at every tool boundary so
	# an internally looping process can be interrupted before final accounting.
	HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION="${HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION:-500000}"
	# Multiple individually bounded episodes must not quietly make one leaf
	# pathological. This budget counts only implementation-worker usage for one
	# immutable task/revision; manager and Oracle scaffolding remain separate.
	HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS="${HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS:-500000}"
	# Relative efficiency detectors complement, but never replace or raise, the
	# three absolute 500K investigation fuses above. Existing projects establish
	# their no-gain baseline lazily so deployment cannot create retroactive
	# incidents from already-accounted history.
	HARNESS_IRREGULARITY_DETECTION_ENABLED="${HARNESS_IRREGULARITY_DETECTION_ENABLED:-1}"
	HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT="${HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT:-300}"
	HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES="${HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES:-5}"
	HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT="${HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT:-2}"
	HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET="${HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET:-3}"
	HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET="${HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET:-500000}"
	HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT="${HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT:-1000}"
	HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS="${HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS:-100000}"
	HARNESS_MAX_STATE_OSCILLATIONS="${HARNESS_MAX_STATE_OSCILLATIONS:-3}"
	HARNESS_MAX_PATCH_CHURN_ROUNDS="${HARNESS_MAX_PATCH_CHURN_ROUNDS:-2}"
	# Normalizing a large, imported specification can legitimately emit hundreds
	# of obligations and relations in one atomic transaction. Keep it bounded,
	# but give that named startup phase a separate budget from ordinary turns.
	HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION="${HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION:-8000000}"
	HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION="${HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION:-2000000}"
	# Retained only for backwards-compatible environment parsing. Provider
	# retries are intentionally unlimited regardless of this legacy value.
	HARNESS_CAPACITY_RETRY_SECONDS="$HARNESS_PROVIDER_RETRY_SECONDS"
	HARNESS_CAPACITY_MAX_RETRIES="${HARNESS_CAPACITY_MAX_RETRIES:-0}"
	# A bounded leaf should not need an unbounded provider process. Long builds
	# still have thirty minutes; workspace changes survive watchdog termination.
	HARNESS_CODEX_WALL_TIMEOUT_SECONDS="${HARNESS_CODEX_WALL_TIMEOUT_SECONDS:-1800}"
	HARNESS_CODEX_IDLE_TIMEOUT_SECONDS="${HARNESS_CODEX_IDLE_TIMEOUT_SECONDS:-0}"
	HARNESS_CODEX_KILL_GRACE_SECONDS="${HARNESS_CODEX_KILL_GRACE_SECONDS:-15}"
	WORKER_HEARTBEAT_SECONDS="${WORKER_HEARTBEAT_SECONDS:-60}"

	MANAGER_MODEL="${MANAGER_MODEL:-gpt-5.6-terra}"
	MANAGER_REASONING_EFFORT="${MANAGER_REASONING_EFFORT:-high}"
	# Global specification normalization and DAG decomposition are performed by
	# a separate, fresh high-capability role. Routine planning and review remain
	# on the less expensive persistent manager.
	DECOMPOSITION_MODEL="${DECOMPOSITION_MODEL:-gpt-5.6-sol}"
	DECOMPOSITION_REASONING_EFFORT="${DECOMPOSITION_REASONING_EFFORT:-high}"
	MANAGER_SANDBOX="${MANAGER_SANDBOX:-workspace-write}"
	WORKER_MODEL="${WORKER_MODEL:-gpt-5.6-luna}"
	WORKER_REASONING_EFFORT="${WORKER_REASONING_EFFORT:-high}"
	WORKER_SANDBOX="${WORKER_SANDBOX:-workspace-write}"
	LUNA_WORKER_MODEL="${LUNA_WORKER_MODEL:-$WORKER_MODEL}"
	LUNA_WORKER_REASONING_EFFORT="${LUNA_WORKER_REASONING_EFFORT:-$WORKER_REASONING_EFFORT}"
	TERRA_WORKER_MODEL="${TERRA_WORKER_MODEL:-$MANAGER_MODEL}"
	TERRA_WORKER_REASONING_EFFORT="${TERRA_WORKER_REASONING_EFFORT:-$MANAGER_REASONING_EFFORT}"
	MANAGER_FALLBACK_MODEL="${MANAGER_FALLBACK_MODEL:-gpt-5.6-terra}"
	WORKER_FALLBACK_MODEL="${WORKER_FALLBACK_MODEL:-gpt-5.6-luna}"
	ORACLE_MODEL="${ORACLE_MODEL:-}"
	ORACLE_FALLBACK_MODEL="${ORACLE_FALLBACK_MODEL:-$MANAGER_FALLBACK_MODEL}"
	ORACLE_ENABLED="${ORACLE_ENABLED:-$([[ -n "$ORACLE_MODEL" ]] && printf 1 || printf 0)}"
	# MAX_ORACLE_RUNS supersedes the legacy ORACLE_ENABLED switch when present.
	# Leave it empty to preserve the legacy unbounded final-audit behavior.
	MAX_ORACLE_RUNS="${MAX_ORACLE_RUNS:-}"
	if [[ -n "$MAX_ORACLE_RUNS" ]]; then
		ORACLE_ENABLED="$([[ "$MAX_ORACLE_RUNS" == 0 ]] && printf 0 || printf 1)"
	fi
	if [[ "$ORACLE_ENABLED" == 1 && -z "$ORACLE_MODEL" ]]; then
		ORACLE_MODEL="gpt-5.6-sol"
	fi
	ORACLE_REASONING_EFFORT="${ORACLE_REASONING_EFFORT:-xhigh}"
	ORACLE_SANDBOX="${ORACLE_SANDBOX:-$MANAGER_SANDBOX}"
	if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
		# Normalize every inference role before callers construct an invocation.
		# The process launcher independently verifies the requested model so a
		# stale or external caller cannot bypass this policy.
		MANAGER_MODEL="$LUNA_WORKER_MODEL"
		MANAGER_REASONING_EFFORT="$LUNA_WORKER_REASONING_EFFORT"
		DECOMPOSITION_MODEL="$LUNA_WORKER_MODEL"
		DECOMPOSITION_REASONING_EFFORT="$LUNA_WORKER_REASONING_EFFORT"
		TERRA_WORKER_MODEL="$LUNA_WORKER_MODEL"
		TERRA_WORKER_REASONING_EFFORT="$LUNA_WORKER_REASONING_EFFORT"
		MANAGER_FALLBACK_MODEL="$LUNA_WORKER_MODEL"
		WORKER_FALLBACK_MODEL="$LUNA_WORKER_MODEL"
		ORACLE_FALLBACK_MODEL="$LUNA_WORKER_MODEL"
		if [[ "$ORACLE_ENABLED" == 1 ]]; then
			ORACLE_MODEL="$LUNA_WORKER_MODEL"
			ORACLE_REASONING_EFFORT="$LUNA_WORKER_REASONING_EFFORT"
		fi
	fi

	MANAGER_CODEX_BIN="${MANAGER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	WORKER_CODEX_BIN="${WORKER_CODEX_BIN:-${CODEX_BIN:-codex}}"
	MANAGER_CODEX_HOME="${MANAGER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	WORKER_CODEX_HOME="${WORKER_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
	ORACLE_CODEX_BIN="${ORACLE_CODEX_BIN:-$MANAGER_CODEX_BIN}"
	ORACLE_CODEX_HOME="${ORACLE_CODEX_HOME:-$MANAGER_CODEX_HOME}"
	MANAGER_CODEX_BIN="$(resolve_command_path "$MANAGER_CODEX_BIN")"
	WORKER_CODEX_BIN="$(resolve_command_path "$WORKER_CODEX_BIN")"
	MANAGER_CODEX_HOME="$(resolve_from_env_dir "$MANAGER_CODEX_HOME")"
	WORKER_CODEX_HOME="$(resolve_from_env_dir "$WORKER_CODEX_HOME")"
	ORACLE_CODEX_BIN="$(resolve_command_path "$ORACLE_CODEX_BIN")"
	ORACLE_CODEX_HOME="$(resolve_from_env_dir "$ORACLE_CODEX_HOME")"

	HARNESS_MANAGER_INVOKER="${HARNESS_MANAGER_INVOKER:-}"
	HARNESS_MANAGER_PLAN_INVOKER="${HARNESS_MANAGER_PLAN_INVOKER:-}"
	HARNESS_MANAGER_REPLAN_INVOKER="${HARNESS_MANAGER_REPLAN_INVOKER:-}"
	HARNESS_WORKER_INVOKER="${HARNESS_WORKER_INVOKER:-}"
	HARNESS_ORACLE_INVOKER="${HARNESS_ORACLE_INVOKER:-}"
	if [[ -n "$HARNESS_MANAGER_INVOKER" ]]; then
		HARNESS_MANAGER_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_INVOKER")"
	fi
	if [[ -n "$HARNESS_MANAGER_PLAN_INVOKER" ]]; then
		HARNESS_MANAGER_PLAN_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_PLAN_INVOKER")"
	fi
	if [[ -n "$HARNESS_MANAGER_REPLAN_INVOKER" ]]; then
		HARNESS_MANAGER_REPLAN_INVOKER="$(resolve_command_path "$HARNESS_MANAGER_REPLAN_INVOKER")"
	fi
	if [[ -n "$HARNESS_WORKER_INVOKER" ]]; then
		HARNESS_WORKER_INVOKER="$(resolve_command_path "$HARNESS_WORKER_INVOKER")"
	fi
	if [[ -n "$HARNESS_ORACLE_INVOKER" ]]; then
		HARNESS_ORACLE_INVOKER="$(resolve_command_path "$HARNESS_ORACLE_INVOKER")"
	fi

	local -a shared_codex_extra_args manager_codex_extra_args worker_codex_extra_args oracle_codex_extra_args
	shared_codex_extra_args=()
	manager_codex_extra_args=()
	worker_codex_extra_args=()
	oracle_codex_extra_args=()
	load_codex_extra_args shared_codex_extra_args CODEX_EXTRA_ARGS
	load_codex_extra_args manager_codex_extra_args MANAGER_CODEX_EXTRA_ARGS
	load_codex_extra_args worker_codex_extra_args WORKER_CODEX_EXTRA_ARGS
	if declare -p ORACLE_CODEX_EXTRA_ARGS >/dev/null 2>&1; then
		load_codex_extra_args oracle_codex_extra_args ORACLE_CODEX_EXTRA_ARGS
	else
		oracle_codex_extra_args=("${manager_codex_extra_args[@]}")
	fi
	MANAGER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${manager_codex_extra_args[@]}")
	WORKER_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${worker_codex_extra_args[@]}")
	ORACLE_CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}" "${oracle_codex_extra_args[@]}")
	if (( ${#shared_codex_extra_args[@]} > 0 )); then
		CODEX_EXTRA_ARGS=("${shared_codex_extra_args[@]}")
	else
		unset CODEX_EXTRA_ARGS
	fi

	validate_project "$PROJECT"
	[[ "$HARNESS_POLL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'HARNESS_POLL_SECONDS must be numeric'
	[[ "$HARNESS_WAIT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_WAIT_SECONDS must be an integer'
	[[ "$HARNESS_STALE_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_STALE_SECONDS must be an integer'
	[[ "$WORKER_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || die 'WORKER_HEARTBEAT_SECONDS must be an integer'
	(( WORKER_HEARTBEAT_SECONDS > 0 )) || die 'WORKER_HEARTBEAT_SECONDS must be greater than zero'
	[[ "$HARNESS_USE_INOTIFY" =~ ^[01]$ ]] || die 'HARNESS_USE_INOTIFY must be 0 or 1'
	[[ "$HARNESS_BOOT_RECOVERY" =~ ^[01]$ ]] || die 'HARNESS_BOOT_RECOVERY must be 0 or 1'
	[[ "$HARNESS_MAX_IDENTICAL_BLOCKERS" =~ ^[0-9]+$ ]] || die 'HARNESS_MAX_IDENTICAL_BLOCKERS must be a nonnegative integer'
	[[ "$HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS must be a positive integer'
	[[ "$HARNESS_MAX_IDENTICAL_RESOURCE_FUSES" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_IDENTICAL_RESOURCE_FUSES must be a positive integer'
	[[ "$HARNESS_MAX_ROOT_ATTEMPTS" =~ ^[0-9]+$ ]] || die 'HARNESS_MAX_ROOT_ATTEMPTS must be a nonnegative integer'
	[[ "$HARNESS_MAX_ZERO_GAIN_WINDOW" =~ ^[0-9]+$ ]] || die 'HARNESS_MAX_ZERO_GAIN_WINDOW must be a nonnegative integer'
	[[ "$HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION" =~ ^[0-9]+$ ]] || die 'HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION must be a nonnegative integer'
	[[ "$HARNESS_MAX_TOTAL_ROOT_REVIEWS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_TOTAL_ROOT_REVIEWS must be a positive integer'
	[[ "$HARNESS_MAX_TOTAL_ROOT_REPLANS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_TOTAL_ROOT_REPLANS must be a positive integer'
	[[ "$HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION must be a positive integer'
	[[ "$HARNESS_MAX_ROOT_CHILD_CRITERIA" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_ROOT_CHILD_CRITERIA must be a positive integer'
	[[ "$HARNESS_MAX_CRITERION_DEPTH" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_CRITERION_DEPTH must be a positive integer'
	[[ "$HARNESS_MAX_ROOT_LIFETIME_SECONDS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_ROOT_LIFETIME_SECONDS must be a positive integer'
	[[ "$HARNESS_MAX_ROOT_PROCESSED_TOKENS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_ROOT_PROCESSED_TOKENS must be a positive integer'
	[[ "$HARNESS_IRREGULARITY_DETECTION_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_IRREGULARITY_DETECTION_ENABLED must be 0 or 1'
	for irregularity_positive_name in HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT \
		HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT \
		HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET \
		HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS \
		HARNESS_MAX_STATE_OSCILLATIONS HARNESS_MAX_PATCH_CHURN_ROUNDS; do
		[[ "${!irregularity_positive_name}" =~ ^[1-9][0-9]*$ ]] ||
			die "$irregularity_positive_name must be a positive integer"
	done
	[[ "$HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD must be a positive integer'
	[[ "$HARNESS_AUTO_REPLAN_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_AUTO_REPLAN_ENABLED must be 0 or 1'
	[[ "$HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN must be a positive integer'
	[[ "$HARNESS_REUSE_WORKER_THREADS" =~ ^[01]$ ]] || die 'HARNESS_REUSE_WORKER_THREADS must be 0 or 1'
	[[ "$HARNESS_WORKER_THREAD_MAX_REJECTIONS" =~ ^[0-9]+$ ]] || die 'HARNESS_WORKER_THREAD_MAX_REJECTIONS must be a nonnegative integer'
	[[ "$HARNESS_CLOSURE_MODE_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_CLOSURE_MODE_ENABLED must be 0 or 1'
	validate_percent "$HARNESS_CLOSURE_MODE_MIN_PROGRESS" 'HARNESS_CLOSURE_MODE_MIN_PROGRESS'
	[[ "$HARNESS_CLOSURE_MODE_MAX_FIXES" =~ ^[0-9]+$ ]] || die 'HARNESS_CLOSURE_MODE_MAX_FIXES must be a nonnegative integer'
	[[ "$HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS must be a positive integer'
	(( HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS > HARNESS_CLOSURE_MODE_MAX_FIXES )) || die 'HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS must be greater than HARNESS_CLOSURE_MODE_MAX_FIXES'
	[[ "$HARNESS_WORKER_GOAL_MODE" =~ ^[01]$ ]] || die 'HARNESS_WORKER_GOAL_MODE must be 0 or 1'
	[[ "$HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS must be a positive integer'
	[[ "$HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS must be a positive integer'
	[[ "$HARNESS_GOAL_PROCESS_MAX_FIXES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_GOAL_PROCESS_MAX_FIXES must be a positive integer'
	[[ "$HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS must be a positive integer'
	[[ "$HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED" =~ ^[01]$ ]] ||
		die 'HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED must be 0 or 1'
	(( HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS >= HARNESS_GOAL_PROCESS_MAX_FIXES )) ||
		die 'HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS must be at least HARNESS_GOAL_PROCESS_MAX_FIXES'
	[[ "$HARNESS_DECOMPOSITION_V2" =~ ^[01]$ ]] || die 'HARNESS_DECOMPOSITION_V2 must be 0 or 1'
	[[ "$HARNESS_DECOMPOSITION_CRITIC_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_DECOMPOSITION_CRITIC_ENABLED must be 0 or 1'
	[[ "$HARNESS_SPECIFICATION_REVIEW_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_SPECIFICATION_REVIEW_ENABLED must be 0 or 1'
	[[ "$HARNESS_MODEL_POLICY" =~ ^(legacy|luna_only)$ ]] ||
		die 'HARNESS_MODEL_POLICY must be legacy or luna_only'
	[[ "$HARNESS_ESCALATION_POLICY" =~ ^(legacy|decompose)$ ]] ||
		die 'HARNESS_ESCALATION_POLICY must be legacy or decompose'
	if [[ "$HARNESS_MODEL_POLICY" == luna_only && "$HARNESS_ESCALATION_POLICY" != decompose ]]; then
		die 'HARNESS_MODEL_POLICY=luna_only requires HARNESS_ESCALATION_POLICY=decompose'
	fi
	[[ "$HARNESS_REPOSITORY_INDEX_MODE" =~ ^(off|advisory|required)$ ]] ||
		die 'HARNESS_REPOSITORY_INDEX_MODE must be off, advisory, or required'
	[[ "$HARNESS_REPOSITORY_OVERLAY_MODE" =~ ^(off|tracked)$ ]] ||
		die 'HARNESS_REPOSITORY_OVERLAY_MODE must be off or tracked'
	[[ "$HARNESS_CONTEXT_CLOSURE_MODE" =~ ^(off|advisory|required|patch_only)$ ]] ||
		die 'HARNESS_CONTEXT_CLOSURE_MODE must be off, advisory, required, or patch_only'
	[[ "$HARNESS_RECOLL_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_RECOLL_ENABLED must be 0 or 1'
	[[ "$HARNESS_JOERN_ENABLED" =~ ^[01]$ ]] || die 'HARNESS_JOERN_ENABLED must be 0 or 1'
	[[ "$HARNESS_JOERN_EXECUTION_MODE" =~ ^(eager|on_demand)$ ]] ||
		die 'HARNESS_JOERN_EXECUTION_MODE must be eager or on_demand'
	[[ "$HARNESS_JOERN_ANALYSIS_CLASSES" =~ ^[A-Za-z0-9,_-]+$ ]] ||
		die 'HARNESS_JOERN_ANALYSIS_CLASSES contains invalid characters'
	[[ "$HARNESS_JOERN_SOURCE_ROOT" != /* && "$HARNESS_JOERN_SOURCE_ROOT" != .. &&
		"$HARNESS_JOERN_SOURCE_ROOT" != ../* && "$HARNESS_JOERN_SOURCE_ROOT" != */../* &&
		"$HARNESS_JOERN_SOURCE_ROOT" != */.. ]] || die 'HARNESS_JOERN_SOURCE_ROOT must remain inside the repository'
	[[ "$HARNESS_JOERN_EXCLUDE_REGEX" != *$'\n'* && "$HARNESS_JOERN_EXCLUDE_REGEX" != *$'\r'* ]] ||
		die 'HARNESS_JOERN_EXCLUDE_REGEX must be a single-line regular expression'
	[[ "$HARNESS_JOERN_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_JOERN_TIMEOUT_SECONDS must be a positive integer'
	[[ "$HARNESS_JOERN_MAX_HEAP_MB" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_JOERN_MAX_HEAP_MB must be a positive integer'
	[[ "$HARNESS_JOERN_MAX_CPUS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_JOERN_MAX_CPUS must be a positive integer'
	[[ "$HARNESS_JOERN_NICE_LEVEL" =~ ^([0-9]|1[0-9])$ ]] ||
		die 'HARNESS_JOERN_NICE_LEVEL must be an integer from 0 through 19'
	[[ "$HARNESS_REPOSITORY_INDEX_RETENTION" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_REPOSITORY_INDEX_RETENTION must be a positive integer'
	[[ "$HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES must be a positive integer'
	[[ "$HARNESS_SCIP_CLANG_JOBS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_SCIP_CLANG_JOBS must be a positive integer'
	local context_closure_limit_name
	for context_closure_limit_name in HARNESS_CONTEXT_CLOSURE_MAX_BYTES HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES \
		HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS HARNESS_CONTEXT_CLOSURE_MAX_MODULES \
		HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES \
		HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS HARNESS_CONTEXT_CLOSURE_MAX_TESTS \
		HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS \
		HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS HARNESS_CONTEXT_EXPANSION_MAX_BYTES; do
		[[ "${!context_closure_limit_name}" =~ ^[1-9][0-9]*$ ]] ||
			die "$context_closure_limit_name must be a positive integer"
	done
	[[ "$HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF" =~ ^[0-9]+$ ]] ||
		die 'HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF must be a non-negative integer'
	[[ "$HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS must be a positive integer'
	(( HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES >= 8192 )) ||
		die 'HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES must be at least 8192'
	(( HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES >= 16384 )) ||
		die 'HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES must be at least 16384'
	(( HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES >= 32768 )) ||
		die 'HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES must be at least 32768'
	for context_closure_percent_name in HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT \
		HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT; do
		[[ "${!context_closure_percent_name}" =~ ^([0-9]|[1-9][0-9]|100)$ ]] ||
			die "$context_closure_percent_name must be an integer from 0 through 100"
	done
	[[ "$HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES must be a positive integer'
	if [[ "$HARNESS_CONTEXT_CLOSURE_MODE" != off && "$HARNESS_REPOSITORY_INDEX_MODE" == off ]]; then
		die 'HARNESS_CONTEXT_CLOSURE_MODE requires HARNESS_REPOSITORY_INDEX_MODE=advisory or required'
	fi
	(( HARNESS_DECOMPOSITION_V2 == 0 || HARNESS_WORKER_GOAL_MODE == 1 )) ||
		die 'HARNESS_DECOMPOSITION_V2=1 requires HARNESS_WORKER_GOAL_MODE=1'
	(( HARNESS_DECOMPOSITION_CRITIC_ENABLED == 0 || HARNESS_DECOMPOSITION_V2 == 1 )) ||
		die 'HARNESS_DECOMPOSITION_CRITIC_ENABLED=1 requires HARNESS_DECOMPOSITION_V2=1'
	(( HARNESS_SPECIFICATION_REVIEW_ENABLED == 0 || HARNESS_DECOMPOSITION_V2 == 1 )) ||
		die 'HARNESS_SPECIFICATION_REVIEW_ENABLED=1 requires HARNESS_DECOMPOSITION_V2=1'
	[[ "$HARNESS_MAX_LUNA_STRATEGY_FAILURES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_LUNA_STRATEGY_FAILURES must be a positive integer'
	[[ "$HARNESS_MAX_LUNA_ALLOWED_PATHS" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_LUNA_ALLOWED_PATHS must be a positive integer'
	[[ "$HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF must be a positive integer'
	[[ "$HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES must be a positive integer'
	local complexity_limit_name
	for complexity_limit_name in \
		HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS HARNESS_MAX_LUNA_FAILURE_PATHS \
		HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES \
		HARNESS_MAX_LUNA_VALIDATION_SURFACES HARNESS_MAX_LUNA_IMPLEMENTATION_FILES \
		HARNESS_MAX_LUNA_REQUIRED_SYMBOLS HARNESS_MAX_LUNA_PREDICTED_ACTIONS \
		HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS \
		HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS HARNESS_MAX_LUNA_COMPLEXITY_SCORE \
		HARNESS_MAX_LUNA_RISK_DOMAINS HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT \
		HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES; do
		[[ "${!complexity_limit_name}" =~ ^[1-9][0-9]*$ ]] ||
			die "$complexity_limit_name must be a positive integer"
	done
	(( HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS <= HARNESS_MAX_LUNA_PREDICTED_ACTIONS )) ||
		die 'HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS must not exceed HARNESS_MAX_LUNA_PREDICTED_ACTIONS'
	[[ "$HARNESS_VALIDATION_OUTPUT_MAX_LINES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_VALIDATION_OUTPUT_MAX_LINES must be a positive integer'
	[[ "$HARNESS_VALIDATION_OUTPUT_MAX_BYTES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_VALIDATION_OUTPUT_MAX_BYTES must be a positive integer'
	[[ "$HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES must be a positive integer'
	[[ "$HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES" =~ ^[1-9][0-9]*$ ]] ||
		die 'HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES must be a positive integer'
	[[ "$HARNESS_MIN_LUNA_NODE_PERCENT" =~ ^(0|[1-9][0-9]*)$ ]] ||
		die 'HARNESS_MIN_LUNA_NODE_PERCENT must be an integer from 0 through 100'
	(( HARNESS_MIN_LUNA_NODE_PERCENT <= 100 )) ||
		die 'HARNESS_MIN_LUNA_NODE_PERCENT must be an integer from 0 through 100'
	[[ "$HARNESS_MIN_LUNA_CODING_NODE_PERCENT" =~ ^(0|[1-9][0-9]*)$ ]] ||
		die 'HARNESS_MIN_LUNA_CODING_NODE_PERCENT must be an integer from 0 through 100'
	(( HARNESS_MIN_LUNA_CODING_NODE_PERCENT <= 100 )) ||
		die 'HARNESS_MIN_LUNA_CODING_NODE_PERCENT must be an integer from 0 through 100'
	[[ "$HARNESS_ARCHITECTURE_GUARDS" =~ ^[01]$ ]] || die 'HARNESS_ARCHITECTURE_GUARDS must be 0 or 1'
	(( HARNESS_ARCHITECTURE_GUARDS == 0 || HARNESS_DECOMPOSITION_V2 == 1 )) ||
		die 'HARNESS_ARCHITECTURE_GUARDS=1 requires HARNESS_DECOMPOSITION_V2=1'
	(( HARNESS_ARCHITECTURE_GUARDS == 0 || HARNESS_WORKER_GOAL_MODE == 1 )) ||
		die 'HARNESS_ARCHITECTURE_GUARDS=1 requires HARNESS_WORKER_GOAL_MODE=1'
	[[ "$HARNESS_PREFERRED_WORKER_ROUTE" =~ ^(LUNA|TERRA)$ ]] ||
		die 'HARNESS_PREFERRED_WORKER_ROUTE must be LUNA or TERRA'
	[[ "$HARNESS_AGENT_COMMITS_ENABLED" =~ ^[01]$ ]] ||
		die 'HARNESS_AGENT_COMMITS_ENABLED must be 0 or 1'
	[[ "$HARNESS_PROVIDER_RETRY_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_PROVIDER_RETRY_SECONDS must be an integer'
	(( HARNESS_PROVIDER_RETRY_SECONDS > 0 )) || die 'HARNESS_PROVIDER_RETRY_SECONDS must be greater than zero'
	[[ "$HARNESS_QUOTA_RETRY_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_QUOTA_RETRY_SECONDS must be an integer'
	(( HARNESS_QUOTA_RETRY_SECONDS > 0 )) || die 'HARNESS_QUOTA_RETRY_SECONDS must be greater than zero'
	[[ "$HARNESS_AGENT_MIN_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_AGENT_MIN_INTERVAL_SECONDS must be a non-negative integer'
	[[ "$HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_AGENT_ITEM_HEADROOM" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_AGENT_ITEM_HEADROOM must be a positive integer'
	[[ "$HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS must be a positive integer'
	[[ "$HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT" =~ ^[0-9]+$ ]] || die 'HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT must be a non-negative integer'
	(( HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT <= 100 )) || die 'HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT must not exceed 100'
	[[ "$HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND" =~ ^[0-9]+$ ]] || die 'HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND must be a non-negative integer'
	[[ "$HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS must be a positive integer'
	[[ "$HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION must be a positive integer'
	[[ "$HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS" =~ ^[0-9]+$ ]] || die 'HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS must be a non-negative integer'
	[[ "$HARNESS_START_MAX_AGENT_INVOCATIONS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_START_MAX_AGENT_INVOCATIONS must be a positive integer'
	[[ "$HARNESS_CAPACITY_MAX_RETRIES" =~ ^[0-9]+$ ]] || die 'HARNESS_CAPACITY_MAX_RETRIES must be an integer'
	[[ "$HARNESS_CODEX_WALL_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_CODEX_WALL_TIMEOUT_SECONDS must be an integer'
	[[ "$HARNESS_CODEX_IDLE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die 'HARNESS_CODEX_IDLE_TIMEOUT_SECONDS must be an integer'
	[[ "$HARNESS_CODEX_KILL_GRACE_SECONDS" =~ ^[1-9][0-9]*$ ]] || die 'HARNESS_CODEX_KILL_GRACE_SECONDS must be a positive integer'
	[[ "$MANAGER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_MODEL: $MANAGER_MODEL"
	[[ "$DECOMPOSITION_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid DECOMPOSITION_MODEL: $DECOMPOSITION_MODEL"
	[[ "$WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_MODEL: $WORKER_MODEL"
	[[ "$LUNA_WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid LUNA_WORKER_MODEL: $LUNA_WORKER_MODEL"
	[[ "$TERRA_WORKER_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid TERRA_WORKER_MODEL: $TERRA_WORKER_MODEL"
	[[ "$MANAGER_FALLBACK_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MANAGER_FALLBACK_MODEL: $MANAGER_FALLBACK_MODEL"
	[[ "$WORKER_FALLBACK_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid WORKER_FALLBACK_MODEL: $WORKER_FALLBACK_MODEL"
	[[ "$ORACLE_FALLBACK_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid ORACLE_FALLBACK_MODEL: $ORACLE_FALLBACK_MODEL"
	[[ "$ORACLE_ENABLED" =~ ^[01]$ ]] || die 'ORACLE_ENABLED must be 0 or 1'
	[[ -z "$MAX_ORACLE_RUNS" || "$MAX_ORACLE_RUNS" =~ ^[0-9]+$ ]] || die 'MAX_ORACLE_RUNS must be a non-negative integer'
	if [[ "$ORACLE_ENABLED" == 1 ]]; then
		[[ "$ORACLE_MODEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid ORACLE_MODEL: $ORACLE_MODEL"
	fi
	[[ "$MANAGER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid MANAGER_REASONING_EFFORT: $MANAGER_REASONING_EFFORT"
	[[ "$DECOMPOSITION_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid DECOMPOSITION_REASONING_EFFORT: $DECOMPOSITION_REASONING_EFFORT"
	[[ "$WORKER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid WORKER_REASONING_EFFORT: $WORKER_REASONING_EFFORT"
	[[ "$LUNA_WORKER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid LUNA_WORKER_REASONING_EFFORT: $LUNA_WORKER_REASONING_EFFORT"
	[[ "$TERRA_WORKER_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid TERRA_WORKER_REASONING_EFFORT: $TERRA_WORKER_REASONING_EFFORT"
	[[ "$MANAGER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid MANAGER_SANDBOX: $MANAGER_SANDBOX"
	[[ "$WORKER_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid WORKER_SANDBOX: $WORKER_SANDBOX"
	[[ "$ORACLE_REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh|max)$ ]] || die "invalid ORACLE_REASONING_EFFORT: $ORACLE_REASONING_EFFORT"
	[[ "$ORACLE_SANDBOX" =~ ^(read-only|workspace-write|danger-full-access)$ ]] || die "invalid ORACLE_SANDBOX: $ORACLE_SANDBOX"
	[[ "$MANAGER_CODEX_BIN" != *[[:space:]]* ]] || die 'MANAGER_CODEX_BIN must not contain arguments'
	[[ "$WORKER_CODEX_BIN" != *[[:space:]]* ]] || die 'WORKER_CODEX_BIN must not contain arguments'
	[[ "$ORACLE_CODEX_BIN" != *[[:space:]]* ]] || die 'ORACLE_CODEX_BIN must not contain arguments'
	[[ -d "$HARNESS_HOME" ]] || die "HARNESS_HOME does not exist: $HARNESS_HOME"
	[[ -d "$HARNESS_BIN" ]] || die "HARNESS_BIN does not exist: $HARNESS_BIN"
	validate_domain_profiles_configuration

	local invoked_bin
	if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
		invoked_bin="$(realpath -m "$(dirname "${BASH_SOURCE[1]}")")"
		[[ "$invoked_bin" == "$HARNESS_BIN" ]] || die "this command was launched from $invoked_bin but ENV_FILE selects HARNESS_BIN=$HARNESS_BIN"
	fi

	export HARNESS_ENV_FILE HARNESS_ENV_DIR HARNESS_MODE PROJECT REPOSITORY SPECIFICATION PROJECT_TMP_DIR
	export HARNESS_HOME HARNESS_BIN HARNESS_ROOT HARNESS_POLL_SECONDS HARNESS_WAIT_SECONDS
	export HARNESS_RUNTIME_PATH_PREFIX HARNESS_BOOT_RECOVERY
	export HARNESS_STALE_SECONDS HARNESS_USE_INOTIFY HARNESS_MAX_IDENTICAL_BLOCKERS HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS HARNESS_MAX_IDENTICAL_RESOURCE_FUSES HARNESS_PROVIDER_RETRY_SECONDS HARNESS_QUOTA_RETRY_SECONDS
	export HARNESS_AGENT_MIN_INTERVAL_SECONDS
	export HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION HARNESS_AGENT_ITEM_HEADROOM HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION
	export HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS
	export HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION
	export HARNESS_AGENT_P95_TOKEN_HEADROOM_PERCENT
	export HARNESS_AGENT_BASE_CONTEXT_TOKENS_PER_ROUND
	export HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION
	export HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS
	export HARNESS_IRREGULARITY_DETECTION_ENABLED HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT
	export HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT
	export HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET
	export HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS
	export HARNESS_MAX_STATE_OSCILLATIONS HARNESS_MAX_PATCH_CHURN_ROUNDS
	export HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION
	export HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION
	export HARNESS_MAX_SPECIFICATION_RENORMALIZATIONS HARNESS_START_MAX_AGENT_INVOCATIONS
	export HARNESS_LARGE_DECOMPOSITION_OBLIGATION_THRESHOLD
	export HARNESS_MAX_ROOT_ATTEMPTS HARNESS_MAX_ZERO_GAIN_WINDOW HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION
	export HARNESS_MAX_TOTAL_ROOT_REVIEWS HARNESS_MAX_TOTAL_ROOT_REPLANS
	export HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION
	export HARNESS_MAX_ROOT_CHILD_CRITERIA HARNESS_MAX_CRITERION_DEPTH
	export HARNESS_MAX_ROOT_LIFETIME_SECONDS HARNESS_MAX_ROOT_PROCESSED_TOKENS
	export HARNESS_AUTO_REPLAN_ENABLED HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN
	export HARNESS_MAX_AUTO_REPLANS_WITHOUT_CRITERION
	export HARNESS_REUSE_WORKER_THREADS HARNESS_WORKER_THREAD_MAX_REJECTIONS
	export HARNESS_CLOSURE_MODE_ENABLED HARNESS_CLOSURE_MODE_MIN_PROGRESS HARNESS_CLOSURE_MODE_MAX_FIXES HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS
	export HARNESS_WORKER_GOAL_MODE HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS
	export HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS HARNESS_GOAL_PROCESS_MAX_FIXES
	export HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS
	export HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED
	export HARNESS_DECOMPOSITION_V2 HARNESS_DECOMPOSITION_CRITIC_ENABLED HARNESS_SPECIFICATION_REVIEW_ENABLED
	export HARNESS_DOMAIN_PROFILES
	export HARNESS_MODEL_POLICY HARNESS_ESCALATION_POLICY
	export HARNESS_REPOSITORY_INDEX_MODE HARNESS_REPOSITORY_OVERLAY_MODE HARNESS_CONTEXT_CLOSURE_MODE
	export HARNESS_REPOSITORY_INDEX_ROOT HARNESS_COMPILE_COMMANDS
	export HARNESS_SCIP_CLANG_BIN HARNESS_SCIP_BIN HARNESS_SCIP_IMPORTER_BIN HARNESS_JOERN_BIN HARNESS_JOERN_ENABLED
	export HARNESS_JOERN_ANALYSIS_CLASSES HARNESS_JOERN_SOURCE_ROOT HARNESS_JOERN_EXCLUDE_REGEX HARNESS_JOERN_TIMEOUT_SECONDS HARNESS_JOERN_EXECUTION_MODE
	export HARNESS_JOERN_MAX_HEAP_MB HARNESS_JOERN_MAX_CPUS HARNESS_JOERN_NICE_LEVEL
	export HARNESS_RECOLL_BIN HARNESS_RECOLL_ENABLED HARNESS_REPOSITORY_INDEX_RETENTION
	export HARNESS_REPOSITORY_INDEX_REFRESH_ACCEPTED_LEAVES
	export HARNESS_SCIP_CLANG_JOBS HARNESS_CONTEXT_CLOSURE_MAX_BYTES HARNESS_ARCHITECTURE_FIT_CAPSULE_MAX_BYTES HARNESS_DECOMPOSITION_CAPSULE_MAX_BYTES HARNESS_ARCHITECTURE_BINDING_CAPSULE_MAX_BYTES
	export HARNESS_CONTEXT_CLOSURE_MAX_SYMBOLS HARNESS_CONTEXT_CLOSURE_MAX_MODULES
	export HARNESS_CONTEXT_CLOSURE_MAX_OWNERSHIP_BOUNDARIES
	export HARNESS_CONTEXT_CLOSURE_MAX_DIRECT_RELATIONSHIPS HARNESS_CONTEXT_CLOSURE_MAX_TESTS
	export HARNESS_CONTEXT_CLOSURE_MAX_BUILD_TARGETS
	export HARNESS_CONTEXT_CLOSURE_MAX_ESTIMATED_TOKENS
	export HARNESS_CONTEXT_EXPANSION_MAX_BYTES HARNESS_MAX_CONTEXT_EXPANSIONS_PER_LEAF
	export HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS
	export HARNESS_CONTEXT_CLOSURE_PROMOTION_MIN_SAMPLES HARNESS_CONTEXT_CLOSURE_MIN_FILE_RECALL_PERCENT
	export HARNESS_CONTEXT_CLOSURE_MIN_LUNA_SUCCESS_PERCENT HARNESS_CONTEXT_CLOSURE_MAX_FALSE_BLOCK_PERCENT
	export HARNESS_MAX_LUNA_STRATEGY_FAILURES
	export HARNESS_MAX_LUNA_ALLOWED_PATHS
	export HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES
	export HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS HARNESS_MAX_LUNA_FAILURE_PATHS
	export HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES
	export HARNESS_MAX_LUNA_VALIDATION_SURFACES HARNESS_MAX_LUNA_IMPLEMENTATION_FILES
	export HARNESS_MAX_LUNA_REQUIRED_SYMBOLS HARNESS_MAX_LUNA_PREDICTED_ACTIONS
	export HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS
	export HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS HARNESS_MAX_LUNA_COMPLEXITY_SCORE
	export HARNESS_MAX_LUNA_RISK_DOMAINS HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT
	export HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES HARNESS_MAX_COMPLEXITY_DECOMPOSITION_PASSES
	export HARNESS_VALIDATION_OUTPUT_MAX_LINES HARNESS_VALIDATION_OUTPUT_MAX_BYTES
	export HARNESS_MAX_AGENT_COMMAND_OUTPUT_BYTES HARNESS_MAX_MANAGER_COMMAND_OUTPUT_BYTES
	export HARNESS_MIN_LUNA_NODE_PERCENT HARNESS_MIN_LUNA_CODING_NODE_PERCENT HARNESS_ARCHITECTURE_GUARDS
	export HARNESS_PREFERRED_WORKER_ROUTE HARNESS_AGENT_COMMITS_ENABLED
	export HARNESS_CAPACITY_RETRY_SECONDS HARNESS_CAPACITY_MAX_RETRIES
	export HARNESS_CODEX_WALL_TIMEOUT_SECONDS HARNESS_CODEX_IDLE_TIMEOUT_SECONDS HARNESS_CODEX_KILL_GRACE_SECONDS
	export WORKER_HEARTBEAT_SECONDS
	export MANAGER_CODEX_BIN MANAGER_CODEX_HOME MANAGER_MODEL MANAGER_REASONING_EFFORT MANAGER_SANDBOX
	export DECOMPOSITION_MODEL DECOMPOSITION_REASONING_EFFORT
	export WORKER_CODEX_BIN WORKER_CODEX_HOME WORKER_MODEL WORKER_REASONING_EFFORT WORKER_SANDBOX
	export LUNA_WORKER_MODEL LUNA_WORKER_REASONING_EFFORT TERRA_WORKER_MODEL TERRA_WORKER_REASONING_EFFORT
	export MANAGER_FALLBACK_MODEL WORKER_FALLBACK_MODEL ORACLE_FALLBACK_MODEL
	export ORACLE_MODEL ORACLE_ENABLED MAX_ORACLE_RUNS ORACLE_REASONING_EFFORT ORACLE_SANDBOX ORACLE_CODEX_BIN ORACLE_CODEX_HOME
	export HARNESS_MANAGER_INVOKER HARNESS_MANAGER_PLAN_INVOKER HARNESS_MANAGER_REPLAN_INVOKER
	export HARNESS_WORKER_INVOKER HARNESS_ORACLE_INVOKER
}

load_codex_extra_args()
{
	local dest_name="$1"
	local source_name="$2"
	local decl
	declare -p "$source_name" >/dev/null 2>&1 || return 0
	decl="$(declare -p "$source_name")"
	case "$decl" in
		"declare -a "*|"declare -ax "*)
			local -n dest_ref="$dest_name"
			local -n source_ref="$source_name"
			dest_ref=("${source_ref[@]}")
			;;
		*)
			die "$source_name must be a Bash array, for example: $source_name=(--config key=value)"
			;;
	esac
}

require_repository()
{
	[[ -d "$REPOSITORY" ]] || die "repository directory does not exist: $REPOSITORY"
}

require_manager_configuration()
{
	require_repository
	[[ -n "$SPECIFICATION" ]] || die "SPECIFICATION is not set in $HARNESS_ENV_FILE"
	[[ -f "$SPECIFICATION" ]] || die "specification file does not exist: $SPECIFICATION"
}

require_manager_codex()
{
	require_executable_runtime manager "$MANAGER_CODEX_BIN"
	[[ -d "$MANAGER_CODEX_HOME" ]] || die "MANAGER_CODEX_HOME does not exist: $MANAGER_CODEX_HOME"
}

require_worker_codex()
{
	require_executable_runtime worker "$WORKER_CODEX_BIN"
	[[ -d "$WORKER_CODEX_HOME" ]] || die "WORKER_CODEX_HOME does not exist: $WORKER_CODEX_HOME"
}

oracle_enabled()
{
	[[ "$ORACLE_ENABLED" == 1 ]]
}

oracle_audit_run_count()
{
	local oracle_dir
	oracle_dir="$(project_oracle_dir)"
	[[ -d "$oracle_dir" ]] || { printf '0\n'; return 0; }
	find "$oracle_dir" -maxdepth 1 -type f -name 'audit-[0-9]*.md' -printf . 2>/dev/null | wc -c
}

oracle_audit_budget_exhausted()
{
	[[ -n "$MAX_ORACLE_RUNS" ]] || return 1
	(( $(oracle_audit_run_count) >= MAX_ORACLE_RUNS ))
}

project_oracle_limit_file()
{
	printf '%s/oracle-run-limit.md' "$(project_oracle_dir)"
}

record_oracle_audit_limit()
{
	local oracle_dir marker tmp completed_runs
	oracle_enabled || return 0
	oracle_audit_budget_exhausted || return 0
	oracle_dir="$(project_oracle_dir)"
	mkdir -p "$oracle_dir"
	chmod 700 "$oracle_dir"
	marker="$(project_oracle_limit_file)"
	[[ -f "$marker" ]] && return 0
	completed_runs="$(oracle_audit_run_count)"
	tmp="$marker.tmp.$$"
	{
		printf '# Oracle Audit Run Limit Reached\n\n'
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Max-Oracle-Runs: %s\n\n' "$MAX_ORACLE_RUNS"
		printf 'Completed-Oracle-Runs: %s\n\n' "$completed_runs"
		printf 'Recorded-At: %s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$marker"
	log_event "ORACLE_AUDIT_LIMIT_REACHED max_runs=$MAX_ORACLE_RUNS completed_runs=$completed_runs marker=$marker"
}

require_oracle_codex()
{
	oracle_enabled || return 0
	require_executable_runtime oracle "$ORACLE_CODEX_BIN"
	[[ -d "$ORACLE_CODEX_HOME" ]] || die "ORACLE_CODEX_HOME does not exist: $ORACLE_CODEX_HOME"
}

validate_project()
{
	local project="$1"
	[[ "$project" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid project name: $project"
}

validate_task_id()
{
	local task_id="$1"
	[[ "$task_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid task id: $task_id"
}

validate_session()
{
	local session="$1"
	[[ "$session" =~ ^[A-Za-z0-9][A-Za-z0-9._:@-]*$ ]] || die "invalid session id: $session"
}

validate_goal_id()
{
	local goal_id="$1"
	[[ "$goal_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] ||
		die "invalid goal id: $goal_id"
}

metadata_count()
{
	local file="$1" field="$2"
	awk -v field="$field" '
		index($0, field ":") == 1 {
			rest = substr($0, length(field) + 2)
			if (rest ~ /^[[:space:]]/) count++
		}
		END {print count + 0}
	' "$file"
}

metadata_value()
{
	local file="$1" field="$2"
	awk -v field="$field" '
		index($0, field ":") == 1 {
			value = substr($0, length(field) + 2)
			sub(/^[[:space:]]+/, "", value)
			sub(/[[:space:]]+$/, "", value)
			print value
			exit
		}
	' "$file"
}

trim_surrounding_whitespace()
{
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s\n' "$value"
}

metadata_identifier_list_is_subset()
{
	local candidate="$1" authority="$2" entry allowed authority_entry
	local -a candidate_entries=() authority_entries=()
	[[ -n "$candidate" && "$candidate" != - && "${candidate^^}" != NONE ]] || return 0
	[[ -n "$authority" && "$authority" != - && "${authority^^}" != NONE ]] || return 1
	candidate="${candidate//;/,}"
	authority="${authority//;/,}"
	IFS=',' read -r -a candidate_entries <<< "$candidate"
	IFS=',' read -r -a authority_entries <<< "$authority"
	for entry in "${candidate_entries[@]}"; do
		entry="$(trim_surrounding_whitespace "$entry")"
		[[ -n "$entry" ]] || continue
		allowed=0
		for authority_entry in "${authority_entries[@]}"; do
			authority_entry="$(trim_surrounding_whitespace "$authority_entry")"
			if [[ -n "$authority_entry" && "$entry" == "$authority_entry" ]]; then
				allowed=1
				break
			fi
		done
		(( allowed == 1 )) || return 1
	done
	return 0
}

require_single_metadata_value()
{
	local file="$1" field="$2" context="${3:-document}" count value
	count="$(metadata_count "$file" "$field")"
	(( count == 1 )) || die "$context must contain exactly one $field line"
	value="$(metadata_value "$file" "$field")"
	[[ -n "$value" ]] || die "$context has an empty $field value"
	[[ "$value" != *$'\t'* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
		die "$context $field must be one tab-free line"
	printf '%s\n' "$value"
}

project_dir()
{
	printf '%s/projects/%s' "$HARNESS_ROOT" "$PROJECT"
}

project_tmp_dir()
{
	printf '%s\n' "$PROJECT_TMP_DIR"
}

ensure_project()
{
	local dir config stored_project stored_repository stored_mode
	validate_project "$PROJECT"
	dir="$(project_dir)"
	[[ -d "$dir" ]] || die "project is not initialized for ENV_FILE $HARNESS_ENV_FILE; run harness-init"
	config="$dir/project.conf"
	[[ -f "$config" ]] || die "project configuration is missing: $config"
	stored_project="$(kv_file_value "$config" project)"
	stored_repository="$(kv_file_value "$config" repository)"
	stored_mode="$(kv_file_value "$config" harness_mode 2>/dev/null || true)"
	[[ "$stored_project" == "$PROJECT" ]] || die "ENV_FILE project '$PROJECT' does not match initialized project '$stored_project'"
	[[ "$stored_repository" == "$REPOSITORY" ]] || die "REPOSITORY changed from '$stored_repository' to '$REPOSITORY'; rerun harness-init with $HARNESS_ENV_FILE"
	[[ -z "$stored_mode" || "$stored_mode" == "$HARNESS_MODE" ]] ||
		die "project state was initialized in HARNESS_MODE=$stored_mode, not $HARNESS_MODE"
}

task_base()
{
	local task_id="$1"
	printf '%s-task-%s' "$PROJECT" "$task_id"
}

task_root_id()
{
	local task_id="$1"
	if [[ "$task_id" =~ ^(.+)-revision-[0-9]+$ ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	else
		printf '%s' "$task_id"
	fi
}

task_progress_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.progress.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_assignment_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.root-assignment.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_operator_route_override_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.operator-worker-route-override.env' \
		"$(project_dir)" "$PROJECT" "$root"
}

task_root_architecture_scope_override_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.architecture-scope-override.env' \
		"$(project_dir)" "$PROJECT" "$root"
}

task_root_liveness_epoch_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.liveness-epoch.env' \
		"$(project_dir)" "$PROJECT" "$root"
}

task_context_capsule_file()
{
	printf '%s/control/context-capsules/%s.md' "$(project_dir)" "$(task_base "$1")"
}

bounded_context_emit_tsv_rows_for_ids()
{
	local file="$1" ids="$2"
	[[ -f "$file" ]] || return 0
	awk -F '\t' -v ids="$ids" '
		BEGIN {n=split(ids,v,","); for(i=1;i<=n;i++) if(v[i] != "" && v[i] != "-") wanted[v[i]]=1}
		NR == 1 || ($1 in wanted)
	' "$file"
}

# Compile deterministic build roots and target locations without asking a
# planning agent to inspect repository source or guess its working directory.
emit_plan_node_build_context()
{
	local node_contract="$1" node_validation cmake_file root target found=0 candidate
	node_validation="$(awk -F '\t' '{print $6; exit}' <<< "$node_contract")"
	printf '\n## Deterministic build-system boundaries\n\n'
	printf 'Shell commands execute from the repository root unless they begin with an explicit `cd`. A CMake source path of `.` is valid only when `.` is listed below. Configure every new static build directory in the same validation command before building it.\n\n'
	printf '### CMake source roots\n\n```text\n'
	while IFS= read -r cmake_file; do
		[[ -n "$cmake_file" ]] || continue
		root="${cmake_file%/CMakeLists.txt}"
		[[ "$root" != "$cmake_file" ]] || root='.'
		printf '%s\n' "$root"
	done < <(git -C "$REPOSITORY" ls-files -- 'CMakeLists.txt' ':(glob)**/CMakeLists.txt' | sort -u | head -n 64)
	printf '```\n\n### Validation targets named by this node\n\n```tsv\n'
	printf 'target\tcmake_source_root\n'
	while IFS=$'\t' read -r target cmake_file; do
		[[ -n "$target" ]] || continue
		tr -cs 'A-Za-z0-9_.:+-' '\n' <<< "$node_validation" | grep -Fqx -- "$target" || continue
		root='.'
		if [[ "$cmake_file" == */* ]]; then
			candidate="${cmake_file%/*}"
			while [[ -n "$candidate" && "$candidate" != . ]]; do
				if [[ -f "$REPOSITORY/$candidate/CMakeLists.txt" ]]; then
					root="$candidate"
					break
				fi
				[[ "$candidate" == */* ]] || break
				candidate="${candidate%/*}"
			done
		fi
		printf '%s\t%s\n' "$target" "$root"
		found=1
	done < <(
		while IFS= read -r cmake_file; do
			[[ -f "$REPOSITORY/$cmake_file" ]] || continue
			awk -v file="$cmake_file" '
				match($0, /add_(executable|library|custom_target)[[:space:]]*\([[:space:]]*[A-Za-z0-9_.:+-]+/) {
					value=substr($0,RSTART,RLENGTH)
					sub(/^.*\([[:space:]]*/,"",value)
					printf "%s\t%s\n",value,file
				}
			' "$REPOSITORY/$cmake_file"
		done < <(git -C "$REPOSITORY" ls-files -- 'CMakeLists.txt' ':(glob)**/CMakeLists.txt' '*.cmake' ':(glob)**/*.cmake' | sort -u)
	)
	(( found == 1 )) || printf '%s\t%s\n' '<none-detected>' '-'
	printf '```\n'
}

# Compile global plan, normalized-IR, and architecture authority into the
# complete semantic context for one node.  Agent prompts receive this artifact
# instead of global registry paths, so each subsequent tool round cannot repay
# for unrelated project history.
write_plan_node_context_capsule()
{
	local output="$1" node_id="$2" plan_file state_file decomposition_file
	local obligations_file relations_file coverage_file allocated='-'
	local binding_file binding_row binding_invariants binding_consumes
	local binding_produces binding_edges binding_gates binding_decisions bytes _
	local active_root root_assignment mandatory_git_refs='-' node_contract=''
	[[ -n "$node_id" && "$node_id" != - ]] || die 'bounded context capsule requires a plan node'
	plan_file="$(project_plan_definition_file)"
	state_file="$(project_plan_state_file)"
	decomposition_file="$(project_decomposition_plan_file)"
	if specification_ir_available; then
		obligations_file="$(specification_obligations_file)"
		relations_file="$(specification_relations_file)"
		coverage_file="$(specification_coverage_file)"
		allocated="$(specification_obligations_for_node "$node_id" | paste -sd, -)"
		[[ -n "$allocated" ]] || allocated='-'
	fi
	{
		printf '# Bounded Plan-Node Context\n\n'
		printf 'This file is the complete plan, specification-IR, and architecture context for node `%s`. Do not open the global files from which it was derived.\n\n' "$node_id"
		printf '## Project plan item\n\n```tsv\n'
		awk -F '\t' -v id="$node_id" 'NR == 1 || $1 == id' "$plan_file"
		printf '```\n\n## Project plan state\n\n```tsv\n'
		awk -F '\t' -v id="$node_id" 'NR == 1 || $1 == id' "$state_file"
		printf '```\n\n## Decomposition node\n\n```tsv\n'
		if [[ -f "$decomposition_file" ]]; then
			node_contract="$(awk -F '\t' -v id="$node_id" '$1 == id {print; exit}' "$decomposition_file")"
			awk -F '\t' -v id="$node_id" 'NR == 1 || $1 == id' "$decomposition_file"
		else
			printf 'legacy_plan_item\n%s\n' "$node_id"
		fi
		printf '```\n'
		emit_plan_node_build_context "$node_contract"
		if [[ "$allocated" != - ]]; then
			printf '\n## Allocated obligations\n\n```tsv\n'
			bounded_context_emit_tsv_rows_for_ids "$obligations_file" "$allocated"
			printf '```\n\n## Typed relations touching allocated obligations\n\n```tsv\n'
			awk -F '\t' -v ids="$allocated" '
				BEGIN {n=split(ids,v,","); for(i=1;i<=n;i++) wanted[v[i]]=1}
				NR == 1 || ($3 in wanted) || ($4 in wanted)
			' "$relations_file"
			printf '```\n\n## Coverage\n\n```tsv\n'
			bounded_context_emit_tsv_rows_for_ids "$coverage_file" "$allocated"
			printf '```\n'
		fi
		if (( HARNESS_ARCHITECTURE_GUARDS == 1 )); then
			binding_file="$(architecture_node_bindings_file)"
			binding_row="$(awk -F '\t' -v id="$node_id" '$1 == id {print; exit}' "$binding_file")"
			if [[ -n "$binding_row" ]]; then
				IFS=$'\t' read -r _ binding_invariants binding_consumes binding_produces binding_edges binding_gates <<< "$binding_row"
				binding_decisions="$binding_consumes,$binding_produces"
				printf '\n## Architecture node binding\n\n```tsv\n'
				head -n 1 "$binding_file"
				printf '%s\n' "$binding_row"
				printf '```\n\n## Bound invariants\n\n```tsv\n'
				bounded_context_emit_tsv_rows_for_ids "$(architecture_invariants_file)" "$binding_invariants"
				printf '```\n\n## Bound decisions\n\n```tsv\n'
				bounded_context_emit_tsv_rows_for_ids "$(architecture_decisions_file)" "$binding_decisions"
				printf '```\n\n## Bound edge contracts\n\n```tsv\n'
				bounded_context_emit_tsv_rows_for_ids "$(architecture_edges_file)" "$binding_edges"
				printf '```\n\n## Bound health gates\n\n```tsv\n'
				bounded_context_emit_tsv_rows_for_ids "$(architecture_health_gates_file)" "$binding_gates"
				printf '```\n\n## Decision and health state\n\n```tsv\n'
				bounded_context_emit_tsv_rows_for_ids "$(architecture_decision_ledger_file)" "$binding_decisions"
				bounded_context_emit_tsv_rows_for_ids "$(architecture_health_ledger_file)" "$binding_gates" | tail -n +2
				printf '```\n'
			fi
		fi
		# Git refs are an explicit external dependency contract. Internal DAG
		# node IDs, architecture decision IDs, and the task IDs recorded as
		# verification evidence are never Git refs. A continuation inherits the
		# exact root contract; a new plan node has none unless a published root
		# assignment later establishes one.
		active_root="$(awk -F '\t' -v id="$node_id" '!/^#/ && $1 == id && $2 == "ACTIVE" {print $3; exit}' "$state_file")"
		if [[ -n "$active_root" && "$active_root" != - ]]; then
			root_assignment="$(task_root_assignment_file "$active_root")"
			if [[ -f "$root_assignment" ]]; then
				mandatory_git_refs="$(metadata_value "$root_assignment" Mandatory-Git-Refs)"
			fi
		fi
		[[ -n "$mandatory_git_refs" && "$mandatory_git_refs" != - && "${mandatory_git_refs^^}" != NONE ]] || mandatory_git_refs='NONE'
		printf '\n## Mandatory cross-harness Git refs\n\n```text\n%s\n```\n' "$mandatory_git_refs"
	} > "$output.tmp.$$"
	chmod 600 "$output.tmp.$$"
	bytes="$(wc -c < "$output.tmp.$$" | tr -d '[:space:]')"
	(( bytes <= 65536 )) || die "bounded plan-node context exceeds 65536 bytes: $bytes"
	mv "$output.tmp.$$" "$output"
}

decomposition_provenance_file()
{
	printf '%s/control/decomposition-provenance.env' "$(project_dir)"
}

decomposition_provenance_value()
{
	local file
	file="$(decomposition_provenance_file)"
	[[ -f "$file" ]] || return 1
	kv_file_value "$file" "$1" "${2:-}"
}

decomposition_resource_contract_enabled()
{
	[[ "$(decomposition_provenance_value resource_contract_version 0 2>/dev/null || printf 0)" =~ ^[1-9][0-9]*$ ]]
}

root_luna_strategy_failure_count()
{
	local root assignment result count=0 task_id rejected
	root="$(task_root_id "$1")"
	shopt -s nullglob
	for result in "$(project_dir)"/archive/"$PROJECT-task-$root"*.result.md \
		"$(project_dir)"/archive/"$PROJECT-task-$root"*.checkpoint-result.md; do
		[[ -f "$result" ]] || continue
		task_id="${result##*/}"
		task_id="${task_id#${PROJECT}-task-}"
		task_id="${task_id%.result.md}"
		task_id="${task_id%.checkpoint-result.md}"
		[[ "$(task_root_id "$task_id")" == "$root" ]] || continue
		assignment="$(project_dir)/archive/$(task_base "$task_id").assignment.md"
		[[ -f "$assignment" ]] || continue
		grep -Eq '^Worker-Route:[[:space:]]*LUNA[[:space:]]*$' "$assignment" || continue
		rejected="$(project_dir)/archive/$(task_base "$task_id").rejected.md"
		if ! grep -Eq '^Goal-Outcome:[[:space:]]*(NEEDS_DECOMPOSITION|HARD_BLOCKED)[[:space:]]*$' "$result" &&
			[[ ! -f "$rejected" ]]; then
			continue
		fi
		count=$((count + 1))
	done
	printf '%s\n' "$count"
}

task_root_block_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.blocked.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_replan_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.needs-replan.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_human_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.needs-human.md' "$(project_dir)" "$PROJECT" "$root"
}

task_root_architecture_reassessment_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.architecture-reassessment-required.md' \
		"$(project_dir)" "$PROJECT" "$root"
}

task_root_token_usage_anomaly_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.token-usage-anomaly.md' \
		"$(project_dir)" "$PROJECT" "$root"
}

project_integrity_anomaly_file()
{
	printf '%s/control/project-integrity-anomaly.md' "$(project_dir)"
}

task_resource_anomaly_file()
{
	local task_id="$1"
	printf '%s/control/progress/%s.task-resource-anomaly.md' "$(project_dir)" "$(task_base "$task_id")"
}

task_root_efficiency_baseline_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.efficiency-baseline.env' "$(project_dir)" "$PROJECT" "$root"
}

task_root_efficiency_metrics_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.efficiency.env' "$(project_dir)" "$PROJECT" "$root"
}

project_efficiency_metrics_file()
{
	printf '%s/control/convergence-efficiency.env' "$(project_dir)"
}

project_verified_facet_efficiency_ledger_file()
{
	printf '%s/logs/verified-facet-efficiency.tsv' "$(project_dir)"
}

project_irregularity_ledger_file()
{
	printf '%s/logs/irregularities.tsv' "$(project_dir)"
}

plan_dependency_invalidation_dir()
{
	printf '%s/control/plan-invalidations' "$(project_dir)"
}

plan_dependency_invalidation_file()
{
	local dependency="$1" consumer="${2:-}"
	[[ "$dependency" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || die "invalid plan item ID: $dependency"
	if [[ -n "$consumer" ]]; then
		validate_task_id "$consumer"
		printf '%s/%s--%s.invalidated.md' "$(plan_dependency_invalidation_dir)" "$dependency" "$consumer"
	else
		printf '%s/%s.invalidated.md' "$(plan_dependency_invalidation_dir)" "$dependency"
	fi
}

task_root_waiting_dependency_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.waiting-dependency.md' "$(project_dir)" "$PROJECT" "$root"
}

dependency_request_dir()
{
	printf '%s/control/dependencies' "$(project_dir)"
}

validate_dependency_request_id()
{
	[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid dependency request ID: $1"
}

dependency_request_file()
{
	validate_dependency_request_id "$1"
	printf '%s/%s.waiting.md' "$(dependency_request_dir)" "$1"
}

dependency_requirements_file()
{
	validate_dependency_request_id "$1"
	printf '%s/%s.requirements.tsv' "$(dependency_request_dir)" "$1"
}

validate_dependency_requirements_file()
{
	local file="$1" header dependency_id type target_ref source_hint ancestor required_path description extra count=0
	local -A seen=()
	[[ -f "$file" ]] || die "dependency requirements file does not exist: $file"
	IFS= read -r header < "$file" || die 'dependency requirements file is empty'
	[[ "$header" == $'dependency_id\ttype\ttarget_ref\tsource_hint\trequired_ancestor\trequired_path\tdescription' ]] ||
		die 'dependency requirements header must be: dependency_id<TAB>type<TAB>target_ref<TAB>source_hint<TAB>required_ancestor<TAB>required_path<TAB>description'
	while IFS=$'\t' read -r dependency_id type target_ref source_hint ancestor required_path description extra; do
		[[ -n "$dependency_id" && -n "$type" && -n "$target_ref" && -n "$source_hint" &&
			-n "$ancestor" && -n "$required_path" && -n "$description" && -z "$extra" ]] ||
			die 'every dependency requirement must contain exactly seven nonempty tab-separated fields'
		[[ "$dependency_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid dependency ID: $dependency_id"
		[[ -z "${seen[$dependency_id]:-}" ]] || die "duplicate dependency ID: $dependency_id"
		seen[$dependency_id]=1
		[[ "$type" =~ ^(GIT_REF|GIT_COMMIT)$ ]] || die "unsupported dependency type: $type"
		if [[ "$type" == GIT_REF ]]; then
			[[ "$target_ref" == refs/heads/* ]] || die "Git dependency must target refs/heads: $target_ref"
			git check-ref-format "$target_ref" >/dev/null 2>&1 || die "invalid dependency target ref: $target_ref"
		else
			[[ "$target_ref" =~ ^[0-9a-fA-F]{7,64}$ ]] ||
				die "Git commit dependency must name a 7-64 digit hexadecimal object ID: $target_ref"
		fi
		[[ "$source_hint" == - || "$source_hint" == /* ]] || die "source_hint must be '-' or an absolute repository path: $source_hint"
		[[ "$ancestor" == - || "$ancestor" =~ ^[0-9a-fA-F]{40}$ ]] || die "required_ancestor must be '-' or a full commit ID: $ancestor"
		if [[ "$ancestor" != - ]]; then
			git -C "$REPOSITORY" cat-file -e "$ancestor^{commit}" 2>/dev/null || die "required ancestor is absent from the consumer repository: $ancestor"
		fi
		if [[ "$required_path" != - ]]; then
			[[ "$required_path" != /* && "$required_path" != ../* && "$required_path" != */../* && "$required_path" != *$'\n'* ]] ||
				die "invalid required repository path: $required_path"
		fi
		count=$((count + 1))
	done < <(tail -n +2 "$file")
	(( count > 0 )) || die 'dependency request must contain at least one requirement'
}

dependency_requirement_failure()
{
	local target_ref="$1" ancestor="$2" required_path="$3" commit
	commit="$(git -C "$REPOSITORY" rev-parse --verify "$target_ref^{commit}" 2>/dev/null || true)"
	[[ -n "$commit" ]] || { printf 'missing-ref'; return 0; }
	if [[ "$ancestor" != - ]] && ! git -C "$REPOSITORY" merge-base --is-ancestor "$ancestor" "$commit"; then
		printf 'wrong-ancestry'
		return 0
	fi
	if [[ "$required_path" != - ]] && ! git -C "$REPOSITORY" cat-file -e "$commit:$required_path" 2>/dev/null; then
		printf 'missing-required-path'
		return 0
	fi
	return 1
}

dependency_requirements_satisfied()
{
	local file="$1" dependency_id type target_ref source_hint ancestor required_path description failure
	while IFS=$'\t' read -r dependency_id type target_ref source_hint ancestor required_path description; do
		failure="$(dependency_requirement_failure "$target_ref" "$ancestor" "$required_path" 2>/dev/null || true)"
		[[ -z "$failure" ]] || return 1
	done < <(tail -n +2 "$file")
}

dependency_requirement_failures()
{
	local file="$1" dependency_id type target_ref source_hint ancestor required_path description failure
	while IFS=$'\t' read -r dependency_id type target_ref source_hint ancestor required_path description; do
		failure="$(dependency_requirement_failure "$target_ref" "$ancestor" "$required_path" 2>/dev/null || true)"
		[[ -z "$failure" ]] || printf '%s\t%s\t%s\t%s\n' "$dependency_id" "$failure" "$target_ref" "$description"
	done < <(tail -n +2 "$file")
}

assignment_mandatory_git_refs()
{
	local file="$1" refs ref ref_name pinned_commit resolved_commit
	refs="$(metadata_value "$file" Mandatory-Git-Refs)"
	[[ -n "$refs" && "$refs" != NONE && "$refs" != - ]] || return 0
	refs="${refs//,/;}"
	IFS=';' read -r -a mandatory_ref_list <<< "$refs"
	for ref in "${mandatory_ref_list[@]}"; do
		ref="${ref#"${ref%%[![:space:]]*}"}"
		ref="${ref%"${ref##*[![:space:]]}"}"
		[[ -n "$ref" ]] || continue
		# A local immutable baseline may be named directly by its full object ID.
		# Cross-harness delivery can additionally pin a branch to an expected
		# commit as refs/heads/name=<oid>. Do not reinterpret either form as a
		# branch whose literal name is the hash or contains '=...'.
		if [[ "$ref" =~ ^[[:xdigit:]]{7,64}$ ]]; then
			# A hexadecimal commit-ish is never a branch name. Resolve an
			# available abbreviation to its immutable full object ID; preserve an
			# absent abbreviation verbatim so diagnostics request the object
			# rather than inventing refs/heads/<hash>.
			resolved_commit="$(git -C "$REPOSITORY" rev-parse --verify "$ref^{commit}" 2>/dev/null || true)"
			printf '%s\n' "${resolved_commit:-$ref}"
			continue
		fi
		if [[ "$ref" == *=* ]]; then
			ref_name="${ref%%=*}"
			pinned_commit="${ref#*=}"
			[[ "$pinned_commit" =~ ^[[:xdigit:]]{40}([[:xdigit:]]{24})?$ ]] ||
				die "invalid pinned commit in Mandatory-Git-Refs entry: $ref"
			[[ "$ref_name" == refs/heads/* ]] || ref_name="refs/heads/$ref_name"
			git check-ref-format "$ref_name" >/dev/null 2>&1 ||
				die "invalid Mandatory-Git-Refs entry: $ref"
			printf '%s=%s\n' "$ref_name" "$pinned_commit"
			continue
		fi
		[[ "$ref" == refs/heads/* ]] || ref="refs/heads/$ref"
		git check-ref-format "$ref" >/dev/null 2>&1 || die "invalid Mandatory-Git-Refs entry: $ref"
		printf '%s\n' "$ref"
	done
}

mandatory_git_ref_satisfied()
{
	local requirement="$1" ref expected actual expected_commit
	if [[ "$requirement" == *=* ]]; then
		ref="${requirement%%=*}"
		expected="${requirement#*=}"
		actual="$(git -C "$REPOSITORY" rev-parse --verify "$ref^{commit}" 2>/dev/null || true)"
		expected_commit="$(git -C "$REPOSITORY" rev-parse --verify "$expected^{commit}" 2>/dev/null || true)"
		[[ -n "$actual" && -n "$expected_commit" && "$actual" == "$expected_commit" ]]
		return
	fi
	git -C "$REPOSITORY" rev-parse --verify "$requirement^{commit}" >/dev/null 2>&1
}

assignment_mandatory_git_refs_satisfied()
{
	local file="$1" ref found=0
	while IFS= read -r ref; do
		[[ -n "$ref" ]] || continue
		found=1
		mandatory_git_ref_satisfied "$ref" || return 1
	done < <(assignment_mandatory_git_refs "$file")
	(( found == 1 )) || return 0
}

assignment_missing_mandatory_git_refs()
{
	local file="$1" ref
	while IFS= read -r ref; do
		[[ -n "$ref" ]] || continue
		mandatory_git_ref_satisfied "$ref" || printf '%s\n' "$ref"
	done < <(assignment_mandatory_git_refs "$file")
}

task_root_replanning_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.replanning.md' "$(project_dir)" "$PROJECT" "$root"
}

task_convergence_baseline_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.convergence-baseline' "$(project_dir)" "$PROJECT" "$root"
}

task_progress_history_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.history.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_checkpoint_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.checkpoints.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_criterion_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.criteria.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_criteria_definition_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.criteria-definition.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_criterion_decomposition_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.criterion-decomposition.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_criterion_facets_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.criterion-facets.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_replan_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.replans.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_manager_remediation_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.manager-remediations.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_hard_block_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.hard-blocks.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_root_token_ledger_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.tokens.tsv' "$(project_dir)" "$PROJECT" "$root"
}

task_replan_baseline_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.replan-baseline' "$(project_dir)" "$PROJECT" "$root"
}

validate_criteria_definition_file()
{
	local file="$1" minimum="${2:-1}" header id title evidence extra count=0
	local -A seen=()
	[[ -f "$file" ]] || die "criteria definition does not exist: $file"
	IFS= read -r header < "$file" || die "criteria definition is empty: $file"
	[[ "$header" == $'criterion_id\ttitle\tacceptance_evidence' ]] ||
		die 'criteria definition header must be: criterion_id<TAB>title<TAB>acceptance_evidence'
	while IFS=$'\t' read -r id title evidence extra; do
		[[ -n "$id" && -n "$title" && -n "$evidence" && -z "$extra" ]] ||
			die "each criteria definition row must contain exactly three nonempty tab-separated fields: $file"
		[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] ||
			die "invalid criterion identifier in criteria definition: $id"
		[[ -z "${seen[$id]:-}" ]] || die "duplicate criterion identifier in criteria definition: $id"
		seen[$id]=1
		count=$((count + 1))
	done < <(tail -n +2 "$file")
	(( count >= minimum )) ||
		die "criteria definition requires at least $minimum independently verifiable criterion row(s)"
}

validate_criterion_decomposition_candidate()
{
	local file="$1" expected_parent="$2"
	local header parent child title evidence extra count=0
	local -A seen=()
	[[ -f "$file" ]] || die "criterion decomposition does not exist: $file"
	IFS= read -r header < "$file" || die "criterion decomposition is empty: $file"
	[[ "$header" == $'parent_criterion\tchild_criterion\ttitle\tacceptance_evidence' ]] ||
		die 'criterion decomposition header must be: parent_criterion<TAB>child_criterion<TAB>title<TAB>acceptance_evidence'
	while IFS=$'\t' read -r parent child title evidence extra; do
		[[ -n "$parent" && -n "$child" && -n "$title" && -n "$evidence" && -z "$extra" ]] ||
			die "each criterion decomposition row must contain exactly four nonempty tab-separated fields: $file"
		[[ "$parent" == "$expected_parent" ]] ||
			die "criterion decomposition may refine only the current first unmet criterion: $expected_parent"
		[[ "$child" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] ||
			die "invalid child criterion identifier in decomposition: $child"
		[[ "$child" != "$parent" ]] ||
			die "child criterion cannot equal its parent: $child"
		[[ -z "${seen[$child]:-}" ]] ||
			die "duplicate child criterion identifier in decomposition: $child"
		seen[$child]=1
		count=$((count + 1))
	done < <(tail -n +2 "$file")
	(( count >= 2 )) ||
		die 'criterion decomposition requires at least two ordered, independently verifiable child criteria'
}

task_root_uses_assignment_criteria()
{
	local assignment
	assignment="$(task_root_assignment_file "$1")"
	[[ -f "$assignment" ]] && grep -Eq '^Root-Criterion: [A-Za-z0-9][A-Za-z0-9._:-]*$' "$assignment"
}

task_root_declared_criteria()
{
	local root assignment definition
	root="$(task_root_id "$1")"
	assignment="$(task_root_assignment_file "$root")"
	definition="$(task_criteria_definition_file "$root")"
	if task_root_uses_assignment_criteria "$root"; then
		awk -F': ' '$1 == "Root-Criterion" {print $2}' "$assignment"
	elif [[ -f "$definition" ]]; then
		awk -F '\t' 'NR > 1 {print $1}' "$definition"
	fi
}

task_criterion_children()
{
	local root criterion decomposition
	root="$(task_root_id "$1")"
	criterion="$2"
	decomposition="$(task_criterion_decomposition_file "$root")"
	[[ -f "$decomposition" ]] || return 0
	awk -F '\t' -v parent="$criterion" 'NR > 1 && $1 == parent {print $2}' "$decomposition"
}

recovery_candidate_targets_verified_child()
{
	local root="$1" assignment="$2" candidate="${3:-}" target architecture file
	[[ -f "$assignment" ]] || return 1
	[[ "$(task_verified_item_count "$root")" =~ ^[1-9][0-9]*$ ]] || return 1
	architecture="$(metadata_value "$assignment" Architecture-Decisions)"
	[[ "$architecture" == NONE ]] || return 1
	target="$(metadata_value "$assignment" Target-Criterion)"
	[[ -n "$target" ]] || return 1
	for file in "$candidate" "$(task_criterion_decomposition_file "$root")"; do
		[[ -n "$file" && -f "$file" ]] || continue
		awk -F '\t' -v target="$target" 'NR > 1 && $2 == target {found=1} END {exit found ? 0 : 1}' "$file" && return 0
	done
	return 1
}

task_emit_criterion_leaves()
{
	local root="$1" criterion="$2" ancestry="${3:-}" child
	local -a children=()
	[[ ":$ancestry:" != *":$criterion:"* ]] ||
		die "criterion decomposition cycle detected at: $criterion"
	mapfile -t children < <(task_criterion_children "$root" "$criterion")
	if (( ${#children[@]} == 0 )); then
		printf '%s\n' "$criterion"
		return 0
	fi
	for child in "${children[@]}"; do
		task_emit_criterion_leaves "$root" "$child" "${ancestry:+$ancestry:}$criterion"
	done
}

task_root_leaf_criteria()
{
	local root criterion
	root="$(task_root_id "$1")"
	while IFS= read -r criterion; do
		[[ -n "$criterion" ]] || continue
		task_emit_criterion_leaves "$root" "$criterion"
	done < <(task_root_declared_criteria "$root")
}

task_leaf_criterion_total_count()
{
	task_root_leaf_criteria "$1" | awk 'NF {count++} END {print count + 0}'
}

task_leaf_criterion_passed_count()
{
	local root criterion count=0
	root="$(task_root_id "$1")"
	while IFS= read -r criterion; do
		[[ -n "$criterion" ]] || continue
		if task_criterion_is_passed "$root" "$criterion"; then
			count=$((count + 1))
		fi
	done < <(task_root_leaf_criteria "$root")
	printf '%s\n' "$count"
}

task_leaf_progress_percent()
{
	local total passed
	total="$(task_leaf_criterion_total_count "$1")"
	passed="$(task_leaf_criterion_passed_count "$1")"
	if (( total == 0 )); then
		printf '0\n'
	else
		printf '%s\n' "$((passed * 100 / total))"
	fi
}

task_criterion_has_pass_record()
{
	local root criterion ledger
	root="$(task_root_id "$1")"
	criterion="$2"
	ledger="$(task_criterion_ledger_file "$root")"
	[[ -f "$ledger" ]] &&
		awk -F '\t' -v item="$criterion" 'NR > 1 && $1 == item && $2 == "PASSED" {found=1} END {exit !found}' "$ledger"
}

task_criterion_is_passed()
{
	local root criterion child
	local -a children=()
	root="$(task_root_id "$1")"
	criterion="$2"
	if task_criterion_has_pass_record "$root" "$criterion"; then
		return 0
	fi
	mapfile -t children < <(task_criterion_children "$root" "$criterion")
	(( ${#children[@]} > 0 )) || return 1
	for child in "${children[@]}"; do
		task_criterion_is_passed "$root" "$child" || return 1
	done
}

task_first_unmet_criterion()
{
	local root criterion
	root="$(task_root_id "$1")"
	while IFS= read -r criterion; do
		[[ -n "$criterion" ]] || continue
		if ! task_criterion_is_passed "$root" "$criterion"; then
			printf '%s\n' "$criterion"
			return 0
		fi
	done < <(task_root_leaf_criteria "$root")
	return 1
}

task_passed_declared_criterion_count()
{
	local root criterion count=0
	root="$(task_root_id "$1")"
	while IFS= read -r criterion; do
		[[ -n "$criterion" ]] || continue
		if task_criterion_is_passed "$root" "$criterion"; then
			count=$((count + 1))
		fi
	done < <(task_root_declared_criteria "$root")
	printf '%s\n' "$count"
}

task_verified_item_count()
{
	local ledger rows=0
	ledger="$(task_criterion_ledger_file "$1")"
	[[ ! -f "$ledger" ]] || rows="$(( $(wc -l < "$ledger") - 1 ))"
	(( rows >= 0 )) || rows=0
	printf '%s\n' "$rows"
}

task_verified_item_count_at()
{
	local ledger at="$2"
	ledger="$(task_criterion_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk -F '\t' -v at="$at" 'NR > 1 && $5 <= at {count++} END {print count + 0}' "$ledger"
}

task_checkpoint_artifact_dir()
{
	local task_id="$1"
	printf '%s/archive/checkpoints/%s' "$(project_dir)" "$(task_base "$task_id")"
}

goal_control_dir()
{
	printf '%s/control/goals' "$(project_dir)"
}

goal_state_file()
{
	printf '%s/%s.goal' "$(goal_control_dir)" "$(task_base "$1")"
}

goal_iteration_ledger_file()
{
	printf '%s/%s.iterations.tsv' "$(goal_control_dir)" "$(task_base "$1")"
}

goal_thread_file()
{
	printf '%s/%s.thread' "$(goal_control_dir)" "$(task_base "$1")"
}

goal_summary_file()
{
	printf '%s/%s.summary.md' "$(goal_control_dir)" "$(task_base "$1")"
}

goal_continue_marker_file()
{
	printf '%s/%s.continue' "$(goal_control_dir)" "$(task_base "$1")"
}

goal_continuation_decision_file()
{
	local task_id="$1" iteration="$2"
	[[ "$iteration" =~ ^[1-9][0-9]*$ ]] || die 'goal continuation decision iteration must be positive'
	printf '%s/iteration-%04d.manager-decision.md' "$(goal_iteration_archive_dir "$task_id")" "$iteration"
}

goal_iteration_archive_dir()
{
	printf '%s/archive/goal-iterations/%s' "$(project_dir)" "$(task_base "$1")"
}

assignment_uses_goal_mode()
{
	[[ -f "$1" ]] && [[ "$(metadata_value "$1" Execution-Mode)" == LEAF_GOAL ]]
}

task_goal_is_active()
{
	local state_file state
	state_file="$(goal_state_file "$1")"
	[[ -f "$state_file" ]] || return 1
	state="$(kv_file_value "$state_file" state 2>/dev/null || true)"
	[[ "$state" =~ ^(READY|RUNNING|AWAITING_MANAGER_REVIEW|ITERATING|SEMANTIC_REPLAN|STRATEGY_REVIEW|REVIEW)$ ]]
}

require_goal_mode_clean_boundary()
{
	local dir artifact assignment task_id
	dir="$(project_dir)"
	[[ -d "$dir" ]] || return 0
	shopt -s nullglob
	for artifact in "$dir/tasks/$PROJECT-task-"*.ready.md \
		"$dir/running/$PROJECT-task-"*.running.md; do
		[[ -f "$artifact" ]] || continue
		if assignment_uses_goal_mode "$artifact"; then
			(( HARNESS_WORKER_GOAL_MODE == 1 )) ||
				die 'HARNESS_WORKER_GOAL_MODE cannot be disabled while a LEAF_GOAL assignment is active'
		elif (( HARNESS_WORKER_GOAL_MODE == 1 )); then
			die 'HARNESS_WORKER_GOAL_MODE cannot be enabled while a legacy assignment is active'
		fi
	done
	for artifact in "$dir/results/$PROJECT-task-"*.result.md; do
		[[ -f "$artifact" ]] || continue
		task_id="$(task_id_from_filename "$artifact")"
		assignment="$dir/archive/$(task_base "$task_id").assignment.md"
		[[ -f "$assignment" ]] || continue
		if assignment_uses_goal_mode "$assignment"; then
			(( HARNESS_WORKER_GOAL_MODE == 1 )) ||
				die 'HARNESS_WORKER_GOAL_MODE cannot be disabled while a LEAF_GOAL result awaits review'
		elif (( HARNESS_WORKER_GOAL_MODE == 1 )); then
			die 'HARNESS_WORKER_GOAL_MODE cannot be enabled while a legacy result awaits review'
		fi
	done
}

goal_state_set()
{
	local file="$1" key="$2" value="$3" tmp
	[[ -f "$file" ]] || die "goal state does not exist: $file"
	[[ "$key" =~ ^[a-z][a-z0-9_]*$ ]] || die "invalid goal-state key: $key"
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
		die "goal-state value must be one line: $key"
	tmp="$file.tmp.$$"
	awk -F= -v key="$key" -v value="$value" '
		BEGIN {updated=0}
		$1 == key && !updated {print key "=" value; updated=1; next}
		{print}
		END {if (!updated) print key "=" value}
	' "$file" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
}

goal_thread_store()
{
	local task_id="$1" thread_id="$2" context="$3" file tmp
	file="$(goal_thread_file "$task_id")"
	tmp="$file.tmp.$$"
	{
		printf 'task_id=%s\n' "$task_id"
		printf 'goal_id=%s\n' "$(kv_file_value "$(goal_state_file "$task_id")" goal_id)"
		printf 'thread_id=%s\n' "$thread_id"
		printf 'context=%s\n' "$context"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
}

clear_worker_goal_thread_for_task()
{
	local task_id="$1" reason="${2:-fresh-context-required}" state_file
	state_file="$(goal_state_file "$task_id")"
	[[ -f "$state_file" ]] || return 0
	goal_state_set "$state_file" thread_id ""
	goal_state_set "$state_file" thread_context "$reason"
	goal_thread_store "$task_id" "" "$reason"
	log_event "WORKER_GOAL_THREAD_CLEARED task=$task_id root=$(task_root_id "$task_id") reason=$reason"
}

goal_record_manager_decision()
{
	local task_id="$1" decision="$2" state_file reviews prior_decision archive_dir source
	state_file="$(goal_state_file "$task_id")"
	[[ -f "$state_file" ]] || return 0
	reviews="$(kv_file_value "$state_file" manager_reviews 2>/dev/null || printf 0)"
	[[ "$reviews" =~ ^[0-9]+$ ]] || reviews=0
	prior_decision="$(kv_file_value "$state_file" manager_decision 2>/dev/null || true)"
	goal_state_set "$state_file" state "$decision"
	goal_state_set "$state_file" manager_decision "$decision"
	if [[ "$prior_decision" != "$decision" &&
		"$decision" =~ ^(ACCEPTED|CHECKPOINTED|REJECTED|BLOCKED)$ ]]; then
		goal_state_set "$state_file" manager_reviews "$((reviews + 1))"
	fi
	goal_state_set "$state_file" manager_reviewed_at "$(timestamp_utc)"
	goal_state_set "$state_file" updated_at "$(timestamp_utc)"
	record_worker_complexity_outcome "$task_id" "$decision"
	archive_dir="$(project_dir)/archive/goals/$(task_base "$task_id")"
	mkdir -p "$archive_dir"
	chmod 700 "$archive_dir"
	for source in "$state_file" "$(goal_iteration_ledger_file "$task_id")" \
		"$(goal_thread_file "$task_id")" "$(goal_summary_file "$task_id")"; do
		[[ -f "$source" ]] || continue
		install -m 600 "$source" "$archive_dir/${source##*/}"
	done
}

repository_workspace_fingerprint()
{
	if git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		{
			git -C "$REPOSITORY" rev-parse HEAD 2>/dev/null || printf 'UNBORN\n'
			git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all
			git -C "$REPOSITORY" diff --binary --no-ext-diff HEAD 2>/dev/null ||
				git -C "$REPOSITORY" diff --binary --no-ext-diff
			while IFS= read -r -d '' untracked_path; do
				printf 'untracked=%s\t' "$untracked_path"
				if [[ -L "$REPOSITORY/$untracked_path" ]]; then
					printf 'symlink:%s\n' "$(readlink "$REPOSITORY/$untracked_path")"
				else
					sha256sum "$REPOSITORY/$untracked_path"
				fi
			done < <(git -C "$REPOSITORY" ls-files --others --exclude-standard -z)
		} | sha256sum | awk '{print "sha256:" $1}'
	else
		find "$REPOSITORY" -xdev -type f -printf '%P\t%s\t%T@\n' 2>/dev/null |
			LC_ALL=C sort | sha256sum | awk '{print "sha256:" $1}'
	fi
}

require_clean_repository_start_state()
{
	local changes
	git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
		die "repository is not a Git working tree: $REPOSITORY"
	git -C "$REPOSITORY" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1 ||
		die "repository does not have a valid HEAD commit: $REPOSITORY"
	register_harness_generated_review_artifacts
	# spec-review/ and architecture-review/ are harness-owned response channels written before a project
	# has an execution DAG. Its untracked artifacts must survive clarification
	# and renormalization restarts without weakening the clean-source boundary.
	# Tracked modifications, staged additions, deletions, renames, and every
	# unrelated untracked path remain disallowed.
	changes="$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all | awk '
		substr($0, 1, 3) == "?? " && substr($0, 4) ~ /^(spec-review|architecture-review)\// {next}
		{print}
	')"
	if [[ -n "$changes" ]]; then
		printf '%s\n' "$changes" >&2
		die 'repository has staged, unstaged, or non-ignored untracked files; commit or clean it before harness-start'
	fi
}

repository_path_is_in_registered_plan_scope()
{
	local path="$1" scope entry dir artifact assignment task_id
	local -a entries=()
	dir="$(project_dir)"
	while IFS= read -r scope; do
		scope="${scope//;/,}"
		IFS=',' read -r -a entries <<< "$scope"
		for entry in "${entries[@]}"; do
			entry="$(trim_surrounding_whitespace "$entry")"
			entry="${entry%/}"
			[[ -n "$entry" && "$entry" != - ]] || continue
			if [[ "$path" == "$entry" || "$path" == "$entry"/* ]]; then
				return 0
			fi
		done
	done < <(
		if project_plan_uses_dag; then
			awk -F '\t' '
				NR == 1 {for (i=1; i<=NF; i++) if ($i=="allowed_paths") field=i; next}
				field && $field != "" {print $field}
			' "$(project_decomposition_plan_file)"
		fi
		shopt -s nullglob
		for assignment in "$dir/control/progress/$PROJECT-task-"*.root-assignment.md; do
			metadata_value "$assignment" Allowed-Scope
		done
		# A resumed project may contain repository changes from a published
		# continuation whose bounded scope is narrower than (or is an audited
		# remediation of) the original DAG node.  Only live task artifacts are
		# authoritative here; scanning every archived assignment would make stale
		# historical scope a permanent restart exemption.
		for artifact in "$dir/tasks/$PROJECT-task-"*.ready.md \
			"$dir/running/$PROJECT-task-"*.running.md; do
			metadata_value "$artifact" Allowed-Scope
			metadata_value "$artifact" Remediation-Scope
		done
		for artifact in "$dir/results/$PROJECT-task-"*.result.md; do
			task_id="$(task_id_from_filename "$artifact")"
			assignment="$dir/archive/$(task_base "$task_id").assignment.md"
			[[ -f "$assignment" ]] || continue
			metadata_value "$assignment" Allowed-Scope
			metadata_value "$assignment" Remediation-Scope
		done
		# After a rejected remediation result is archived, its needs-replan
		# marker is the live authority bridge to the next bounded continuation.
		# Preserve only its explicit mutation scope; Context-Paths are read
		# authority and must never become a restart write exemption.
		for artifact in "$dir/control/progress/$PROJECT-task-"*.needs-replan.md; do
			metadata_value "$artifact" Remediation-Scope
		done
		# Explicit architecture resolutions persist exact manager-remediation
		# mutation authority in a root-level override. It must remain valid restart
		# attribution after the triggering reassessment marker is archived; otherwise
		# the harness rejects the preserved file it previously authorized.
		for artifact in "$dir/control/progress/$PROJECT-task-"*.architecture-scope-override.env; do
			kv_file_value "$artifact" additional_scope 2>/dev/null || true
		done
		shopt -u nullglob
	)
	return 1
}

require_resumable_repository_start_state()
{
	local changes path unauthorized=""
	git -C "$REPOSITORY" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
		die "repository is not a Git working tree: $REPOSITORY"
	git -C "$REPOSITORY" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1 ||
		die "repository does not have a valid HEAD commit: $REPOSITORY"
	register_harness_generated_review_artifacts
	changes="$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all | awk '
		substr($0, 1, 3) == "?? " && substr($0, 4) ~ /^(spec-review|architecture-review)\// {next}
		{print}
	')"
	if grep -q '^?? ' <<< "$changes"; then
		printf '%s\n' "$changes" >&2
		die 'repository has non-ignored untracked files; commit or clean them before restarting the harness'
	fi
	while IFS= read -r -d '' path; do
		if ! repository_path_is_in_registered_plan_scope "$path"; then
			unauthorized+="${unauthorized:+$'\n'}$path"
		fi
	done < <(git -C "$REPOSITORY" diff --name-only -z HEAD)
	if [[ -n "$unauthorized" ]]; then
		printf '%s\n' "$changes" >&2
		printf 'Tracked restart changes outside registered plan scope:\n%s\n' "$unauthorized" >&2
		die 'repository drift is not attributable to the registered project DAG; commit, clean, or revise the plan before restarting'
	fi
}

harness_generated_review_artifact()
{
	case "$1" in
		spec-review/domain-profiles-*|spec-review/repository-facts-*|\
		spec-review/repository-inventory-*|spec-review/specification-clarifications-*|\
		spec-review/specification-obligations-*|spec-review/specification-relations-*|\
		spec-review/specification-review-*|spec-review/specification-critic-challenge-*|\
		spec-review/specification-critic-issues-*|spec-review/architecture-fit-review-*|\
		architecture-review/architecture-fit-*|architecture-review/architecture-redesign-*|\
		architecture-review/architecture-redesign-issues-*|\
		architecture-review/architecture-redesign-specification-*) return 0 ;;
		*) return 1 ;;
	esac
}

register_harness_generated_review_artifacts()
{
	local git_dir exclude_file lock_file relative artifact exclude_lock_fd
	git_dir="$(git -C "$REPOSITORY" rev-parse --git-dir 2>/dev/null || true)"
	[[ -n "$git_dir" ]] || return 0
	[[ "$git_dir" == /* ]] || git_dir="$REPOSITORY/$git_dir"
	exclude_file="$git_dir/info/exclude"
	lock_file="$git_dir/info/coding-harness-exclude.lock"
	mkdir -p "$git_dir/info"
	exec {exclude_lock_fd}>"$lock_file"
	flock -x "$exclude_lock_fd"
	touch "$exclude_file"
	while IFS= read -r -d '' artifact; do
		relative="${artifact#"$REPOSITORY/"}"
		harness_generated_review_artifact "$relative" || continue
		grep -Fqx "/$relative" "$exclude_file" 2>/dev/null ||
			printf '/%s\n' "$relative" >> "$exclude_file"
	done < <(find "$REPOSITORY/spec-review" "$REPOSITORY/architecture-review" \
		-maxdepth 1 -type f -print0 2>/dev/null)
	flock -u "$exclude_lock_fd"
	exec {exclude_lock_fd}>&-
}

worker_thread_state_file()
{
	local root
	root="$(task_root_id "$1")"
	printf '%s/control/progress/%s-task-%s.worker-thread' "$(project_dir)" "$PROJECT" "$root"
}

codex_thread_id_from_jsonl()
{
	local log_file="$1"
	if command -v jq >/dev/null 2>&1; then
		jq -rs '[.[] | select(.type == "thread.started") | .thread_id][0] // empty' "$log_file" 2>/dev/null
	else
		sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"thread.started".*"thread_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$log_file" | head -n 1
	fi
}

codex_usage_value_from_jsonl()
{
	local log_file="$1" field="$2"
	[[ -f "$log_file" ]] || { printf '0\n'; return 0; }
	if command -v jq >/dev/null 2>&1; then
		jq -rs --arg field "$field" '
			[.[] | select(.type == "turn.completed") | (.usage[$field] // 0)]
			| add // 0
		' "$log_file" 2>/dev/null || printf '0\n'
	else
		printf '0\n'
	fi
}

worker_thread_id_for_task()
{
	local task_id="$1" dir file latest latest_mtime mtime thread_id
	dir="$(project_dir)"
	latest=""
	latest_mtime=-1
	shopt -s nullglob
	for file in "$dir/logs/worker-task-$task_id-"*.jsonl; do
		mtime="$(stat -c %Y "$file" 2>/dev/null || printf 0)"
		if (( mtime > latest_mtime )) || { (( mtime == latest_mtime )) && [[ "$file" > "$latest" ]]; }; then
			latest="$file"
			latest_mtime="$mtime"
		fi
	done
	[[ -n "$latest" ]] || return 1
	thread_id="$(codex_thread_id_from_jsonl "$latest")"
	[[ "$thread_id" =~ ^[A-Za-z0-9-]+$ ]] || return 1
	printf '%s\n' "$thread_id"
}

latest_worker_jsonl_for_task()
{
	local task_id="$1" dir file latest latest_mtime mtime
	dir="$(project_dir)"
	latest=""
	latest_mtime=-1
	shopt -s nullglob
	for file in "$dir/logs/worker-task-$task_id-"*.jsonl; do
		mtime="$(stat -c %Y "$file" 2>/dev/null || printf 0)"
		if (( mtime > latest_mtime )) || { (( mtime == latest_mtime )) && [[ "$file" > "$latest" ]]; }; then
			latest="$file"
			latest_mtime="$mtime"
		fi
	done
	shopt -u nullglob
	[[ -n "$latest" ]] || return 1
	printf '%s\n' "$latest"
}

write_worker_episode_evidence_digest()
{
	local task_id="$1" output_file="$2" json_log classification_file last_message_file tmp
	json_log="$(latest_worker_jsonl_for_task "$task_id" 2>/dev/null || true)"
	tmp="$output_file.tmp.$$"
	{
		printf '# Bounded Worker Episode Evidence\n\n'
		printf 'Task-ID: %s\n' "$task_id"
		if [[ -z "$json_log" ]]; then
			printf 'Worker-Transcript: unavailable\n'
		else
			classification_file="${json_log%.jsonl}.classification"
			last_message_file="${json_log%.jsonl}.md"
			printf 'Worker-Transcript: summarized-locally\n'
			printf 'Worker-JSONL-Bytes: %s\n' "$(stat -c %s "$json_log" 2>/dev/null || printf 0)"
			if [[ -f "$classification_file" ]]; then
				printf '\n## Classification\n\n'
				awk -F= '$1 ~ /^(classification|role|model|exit_status|item_started_count|estimated_processed_tokens|processed_token_limit|resource_guard|git_head_changed|partial_edits|workspace_fingerprint_before|workspace_fingerprint_after|declared_effective_p95|runtime_p95_floor|prompt_bytes|context_rounds)$/ {print}' \
					"$classification_file"
			fi
			if command -v jq >/dev/null 2>&1; then
				printf '\n## Command manifest\n\n'
				jq -sr '
					[.[] | select(.type == "item.completed" and .item.type == "command_execution")][0:40]
					| to_entries[]?
					| .value.item as $item
					| ($item.command // "" | gsub("[\\r\\n\\t]+"; " ") | .[0:360]) as $command
					| ($item.aggregated_output // $item.output // "" | tostring | length) as $bytes
					| "- command[\(.key + 1)] exit=\($item.exit_code // $item.status // "unknown") output_bytes=\($bytes): \($command)"
				' "$json_log" 2>/dev/null || true
				printf '\n## Terminal command evidence (bounded)\n\n'
				jq -sr '
					[.[] | select(.type == "item.completed" and .item.type == "command_execution")][-2:]
					| to_entries[]?
					| .value.item as $item
					| ($item.command // "" | gsub("[\\r\\n\\t]+"; " ") | .[0:360]) as $command
					| ($item.aggregated_output // $item.output // "" | tostring | .[0:4096]) as $output
					| "### terminal-command[\(.key + 1)]\n\($command)\n\n```text\n\($output)\n```\n"
				' "$json_log" 2>/dev/null || true
				printf '\n## Agent messages\n\n'
				jq -sr '
					[.[] | select(.type == "item.completed" and .item.type == "agent_message") | (.item.text // "")]
					| .[-3:][]?
					| gsub("[\\r\\t]"; " ")
					| .[0:2400]
				' "$json_log" 2>/dev/null || true
			fi
			if [[ -s "$last_message_file" ]]; then
				printf '\n## Last message (bounded)\n\n'
				tail -n 80 "$last_message_file" | tail -c 8192
				printf '\n'
			fi
		fi
		printf '\n## Review boundary\n\n'
		printf 'This digest was generated locally. Reviewers must not open the raw worker JSONL, stderr, or raw command/build logs; immediate successor workers must not open them either. Reuse the bounded terminal evidence above instead of repeating those reads, inspect only the next missing exact fact, and run focused validation through harness-run-logged.\n'
	} > "$tmp"
	# A malformed or unexpectedly verbose provider record must never turn the
	# deterministic digest itself into another context-amplification source.
	head -c 32768 "$tmp" > "$output_file"
	rm -f "$tmp"
	chmod 600 "$output_file"
}

retain_worker_thread_for_rejection()
{
	local task_id="$1" root file thread_id previous_thread previous_task rejection_count tmp
	(( HARNESS_REUSE_WORKER_THREADS == 1 )) || return 0
	root="$(task_root_id "$task_id")"
	file="$(worker_thread_state_file "$root")"
	thread_id="$(worker_thread_id_for_task "$task_id" 2>/dev/null || true)"
	if [[ -z "$thread_id" ]]; then
		log_event "WORKER_THREAD_NOT_RETAINED task=$task_id root=$root reason=thread_id_unavailable"
		return 0
	fi
	previous_thread=""
	previous_task=""
	rejection_count=0
	if [[ -f "$file" ]]; then
		previous_thread="$(kv_file_value "$file" thread_id)"
		previous_task="$(kv_file_value "$file" last_rejected_task)"
		rejection_count="$(kv_file_value "$file" rejection_count)"
	fi
	[[ "$rejection_count" =~ ^[0-9]+$ ]] || rejection_count=0
	if [[ "$previous_thread" != "$thread_id" ]]; then
		rejection_count=1
	elif [[ "$previous_task" != "$task_id" ]]; then
		rejection_count=$((rejection_count + 1))
	fi
	tmp="$file.tmp.$$"
	{
		printf 'thread_id=%s\n' "$thread_id"
		printf 'task_root=%s\n' "$root"
		printf 'last_rejected_task=%s\n' "$task_id"
		printf 'rejection_count=%s\n' "$rejection_count"
		printf 'last_outcome=REJECT\n'
		printf 'retained_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
	log_event "WORKER_THREAD_RETAINED task=$task_id root=$root thread_id=$thread_id rejection_count=$rejection_count"
}

retain_worker_thread_for_checkpoint()
{
	local task_id="$1" root file thread_id tmp
	(( HARNESS_REUSE_WORKER_THREADS == 1 )) || return 0
	root="$(task_root_id "$task_id")"
	file="$(worker_thread_state_file "$root")"
	thread_id="$(worker_thread_id_for_task "$task_id" 2>/dev/null || true)"
	if [[ -z "$thread_id" ]]; then
		log_event "WORKER_THREAD_NOT_RETAINED task=$task_id root=$root reason=thread_id_unavailable outcome=checkpoint"
		return 0
	fi
	tmp="$file.tmp.$$"
	{
		printf 'thread_id=%s\n' "$thread_id"
		printf 'task_root=%s\n' "$root"
		printf 'last_checkpointed_task=%s\n' "$task_id"
		printf 'rejection_count=0\n'
		printf 'last_outcome=CHECKPOINT\n'
		printf 'retained_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
	log_event "WORKER_THREAD_CHECKPOINTED task=$task_id root=$root thread_id=$thread_id rejection_count=0"
}

clear_worker_thread_for_root()
{
	local task_id="$1" reason="${2:-resolved}" root file thread_id
	root="$(task_root_id "$task_id")"
	file="$(worker_thread_state_file "$root")"
	[[ -f "$file" ]] || return 0
	thread_id="$(kv_file_value "$file" thread_id 2>/dev/null || printf unknown)"
	rm -f "$file"
	log_event "WORKER_THREAD_CLEARED task=$task_id root=$root thread_id=$thread_id reason=$reason"
}

task_root_is_blocked()
{
	[[ -f "$(task_root_block_file "$1")" ]]
}

task_root_needs_replan()
{
	[[ -f "$(task_root_replan_file "$1")" ]]
}

task_root_needs_human()
{
	[[ -f "$(task_root_human_file "$1")" ]]
}

task_root_needs_architecture_reassessment()
{
	[[ -f "$(task_root_architecture_reassessment_file "$1")" ]]
}

task_root_has_token_usage_anomaly()
{
	[[ -f "$(task_root_token_usage_anomaly_file "$1")" ]]
}

project_has_token_usage_anomaly()
{
	compgen -G "$(project_dir)/control/progress/$PROJECT-task-*.token-usage-anomaly.md" >/dev/null
}

require_no_project_token_usage_anomaly()
{
	project_has_token_usage_anomaly || return 0
	die 'project has an unresolved TOKEN_USAGE_ANOMALY; inspect and resolve it before launching another agent process'
}

project_has_integrity_anomaly()
{
	[[ -f "$(project_integrity_anomaly_file)" ]]
}

require_no_project_integrity_anomaly()
{
	project_has_integrity_anomaly || return 0
	die 'project has an unresolved PROJECT_INTEGRITY_ANOMALY; inspect and explicitly resolve it before launching another agent process'
}

task_has_resource_anomaly()
{
	[[ -f "$(task_resource_anomaly_file "$1")" ]]
}

irregularity_sanitize_field()
{
	printf '%s' "$1" | tr '\t\r\n' '   '
}

record_irregularity()
{
	local severity="$1" category="$2" task_id="${3:--}" scope="${4:--}"
	local reason="${5:--}" evidence="${6:--}" marker="${7:--}"
	local ledger lock
	[[ "$HARNESS_IRREGULARITY_DETECTION_ENABLED" == 1 ]] || return 0
	case "$severity" in
		EFFICIENCY_WARNING|TASK_RESOURCE_ANOMALY|PROJECT_INTEGRITY_ANOMALY) ;;
		*) die "invalid irregularity severity: $severity" ;;
	esac
	ledger="$(project_irregularity_ledger_file)"
	lock="$(project_dir)/control/irregularities.lock"
	mkdir -p "$(dirname "$ledger")" "$(dirname "$lock")"
	exec 4>"$lock"
	flock -x 4
	if [[ ! -f "$ledger" ]]; then
		printf 'recorded_at\tseverity\tcategory\ttask_id\tscope\treason\tevidence\tmarker\n' > "$ledger"
		chmod 600 "$ledger"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$severity" \
		"$(irregularity_sanitize_field "$category")" "$(irregularity_sanitize_field "$task_id")" \
		"$(irregularity_sanitize_field "$scope")" "$(irregularity_sanitize_field "$reason")" \
		"$(irregularity_sanitize_field "$evidence")" "$(irregularity_sanitize_field "$marker")" >> "$ledger"
	flock -u 4
	log_event "IRREGULARITY severity=$severity category=$category task=$task_id scope=$scope marker=$marker reason=$(printf '%q' "$reason")"
}

mark_efficiency_warning()
{
	local category="$1" task_id="${2:--}" reason="${3:--}" evidence="${4:--}"
	local root="-"
	[[ "$task_id" == - ]] || root="$(task_root_id "$task_id")"
	record_irregularity EFFICIENCY_WARNING "$category" "$task_id" "$root" "$reason" "$evidence" -
}

mark_task_resource_anomaly()
{
	local task_id="$1" category="$2" reason="$3" evidence="${4:--}"
	local marker tmp created=0 root
	root="$(task_root_id "$task_id")"
	marker="$(task_resource_anomaly_file "$task_id")"
	mkdir -p "$(dirname "$marker")"
	if [[ ! -f "$marker" ]]; then
		tmp="$marker.tmp.$$"
		{
			printf '# Task Resource Anomaly\n\n'
			printf 'Project: %s\n\nTask-ID: %s\n\nTask-Root: %s\n\n' "$PROJECT" "$task_id" "$root"
			printf 'Category: %s\n\nDetected-At: %s\n\n' "$category" "$(timestamp_utc)"
			printf 'Reason: %s\n\nEvidence: %s\n\n' "$reason" "$evidence"
			printf 'This immutable task revision is quarantined. A smaller successor revision may run after deterministic decomposition; the anomaly record remains durable for investigation.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$marker"
		created=1
	fi
	if (( created == 1 )); then
		record_irregularity TASK_RESOURCE_ANOMALY "$category" "$task_id" "$root" "$reason" "$evidence" "$marker"
	fi
	printf '%s\n' "$marker"
}

mark_project_integrity_anomaly()
{
	local category="$1" task_id="${2:--}" reason="${3:--}" evidence="${4:--}"
	local marker tmp created=0
	marker="$(project_integrity_anomaly_file)"
	mkdir -p "$(dirname "$marker")"
	if [[ ! -f "$marker" ]]; then
		tmp="$marker.tmp.$$"
		{
			printf '# Project Integrity Anomaly\n\n'
			printf 'Project: %s\n\nCategory: %s\n\nTriggered-By: %s\n\n' "$PROJECT" "$category" "$task_id"
			printf 'Paused-At: %s\n\nReason: %s\n\nEvidence: %s\n\n' "$(timestamp_utc)" "$reason" "$evidence"
			printf 'All agent launches are suppressed. Preserve the marker, correct the accounting/closure/model/index policy defect, then use harness-resolve-project-integrity-anomaly with an explicit resolution record.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$marker"
		created=1
	fi
	if (( created == 1 )); then
		record_irregularity PROJECT_INTEGRITY_ANOMALY "$category" "$task_id" project "$reason" "$evidence" "$marker"
	fi
	printf '%s\n' "$marker"
}

task_root_waiting_dependency()
{
	[[ -f "$(task_root_waiting_dependency_file "$1")" ]]
}

task_root_is_replanning()
{
	[[ -f "$(task_root_replanning_file "$1")" ]]
}

task_root_is_paused()
{
	task_root_is_blocked "$1" || task_root_needs_replan "$1" ||
		task_root_needs_human "$1" || task_root_is_replanning "$1" ||
	task_root_waiting_dependency "$1" ||
		task_root_needs_architecture_reassessment "$1" ||
		task_root_has_token_usage_anomaly "$1"
}

task_progress_percent()
{
	local file
	file="$(task_progress_file "$1")"
	if [[ -f "$file" ]]; then
		awk -F': ' '$1 == "Progress-Percent" {gsub(/%/, "", $2); print $2; exit}' "$file"
	else
		printf '0\n'
	fi
}

review_percent()
{
	local file="$1"
	local field="$2"
	awk -F': ' -v field="$field" '$1 == field {gsub(/%/, "", $2); print $2; exit}' "$file"
}

validate_percent()
{
	local value="$1"
	local label="$2"
	[[ "$value" =~ ^(100|[1-9]?[0-9])$ ]] || die "$label must be an integer from 0 through 100"
}

initialize_task_progress()
{
	local task_id="$1"
	local assignment="$2"
	local root progress root_assignment archived_root_assignment tmp
	root="$(task_root_id "$task_id")"
	progress="$(task_progress_file "$root")"
	root_assignment="$(task_root_assignment_file "$root")"
	mkdir -p "$(dirname "$progress")"
	chmod 700 "$(dirname "$progress")"
	if [[ ! -f "$root_assignment" ]]; then
		archived_root_assignment="$(project_dir)/archive/$(task_base "$root").assignment.md"
		if [[ -f "$archived_root_assignment" ]]; then
			install -m 600 "$archived_root_assignment" "$root_assignment"
		else
			install -m 600 "$assignment" "$root_assignment"
		fi
	fi
	if [[ ! -f "$progress" ]]; then
		tmp="$progress.tmp.$$"
		{
			printf '# Root Task Progress\n\n'
			printf 'Project: %s\n' "$PROJECT"
			printf 'Task-Root: %s\n' "$root"
			printf 'Progress-Percent: 0%%\n'
			printf 'Improvement-Percent: 0%%\n'
			printf 'Last-Reviewed-Task: none\n'
			printf 'Updated-At: %s\n\n' "$(timestamp_utc)"
			printf '## Evidence checkpoint\n\nNo reviewed implementation evidence yet.\n\n'
			printf '## Remaining work\n\nReconcile the repository against the root assignment.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$progress"
	fi
	if [[ ! -f "$(task_root_efficiency_baseline_file "$root")" ]]; then
		record_root_verified_facet_boundary "$root"
	fi
}

update_task_progress()
{
	local task_id="$1"
	local progress_percent="$2"
	local improvement_percent="$3"
	local decision="$4"
	local review_file="${5:-}"
	local root progress history review_sha tmp
	root="$(task_root_id "$task_id")"
	progress="$(task_progress_file "$root")"
	validate_percent "$progress_percent" 'Progress-Percent'
	validate_percent "$improvement_percent" 'Improvement-Percent'
	tmp="$progress.tmp.$$"
	{
		printf '# Root Task Progress\n\n'
		printf 'Project: %s\n' "$PROJECT"
		printf 'Task-Root: %s\n' "$root"
		printf 'Progress-Percent: %s%%\n' "$progress_percent"
		printf 'Improvement-Percent: %s%%\n' "$improvement_percent"
		printf 'Last-Reviewed-Task: %s\n' "$task_id"
		printf 'Last-Decision: %s\n' "$decision"
		printf 'Updated-At: %s\n' "$(timestamp_utc)"
		if [[ -n "$review_file" && -f "$review_file" ]]; then
			printf '\n## Evidence checkpoint\n\n'
			cat "$review_file"
			printf '\n'
		fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$progress"
	history="$(task_progress_history_file "$root")"
	if [[ ! -f "$history" ]]; then
		printf 'updated_at\ttask_id\tdecision\tprogress_percent\timprovement_percent\treview_sha256\n' > "$history"
		chmod 600 "$history"
	fi
	review_sha='-'
	if [[ -n "$review_file" && -f "$review_file" ]]; then
		review_sha="$(sha256sum "$review_file" | awk '{print $1}')"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$task_id" "$decision" \
		"$progress_percent" "$improvement_percent" "$review_sha" >> "$history"
	log_event "TASK_PROGRESS_UPDATED root=$root task=$task_id progress=$progress_percent improvement=$improvement_percent decision=$decision"
}

root_reviewed_attempt_count()
{
	local root="$1" dir file count=0 task
	dir="$(project_dir)"
	shopt -s nullglob
	for file in "$dir/archive/$PROJECT-task-"*.accepted.md \
		"$dir/archive/$PROJECT-task-"*.checkpointed.md \
		"$dir/archive/$PROJECT-task-"*.rejected.md \
		"$dir/archive/$PROJECT-task-"*.blocked.md; do
		task="$(task_id_from_filename "$file")"
		task="${task%.accepted.md}"
		task="${task%.checkpointed.md}"
		task="${task%.rejected.md}"
		task="${task%.blocked.md}"
		if [[ "$(task_root_id "$task")" == "$root" ]]; then
			count=$((count + 1))
		fi
	done
	printf '%s\n' "$count"
}

root_total_replan_count()
{
	local ledger rows
	ledger="$(task_replan_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	rows="$(( $(wc -l < "$ledger") - 1 ))"
	(( rows >= 0 )) || rows=0
	printf '%s\n' "$rows"
}

root_child_criterion_count()
{
	local file rows
	file="$(task_criterion_decomposition_file "$1")"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	rows="$(( $(wc -l < "$file") - 1 ))"
	(( rows >= 0 )) || rows=0
	printf '%s\n' "$rows"
}

root_criterion_max_depth()
{
	local file
	file="$(task_criterion_decomposition_file "$1")"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk -F '\t' '
		NR > 1 {
			value = depth[$1] + 1
			if (value > depth[$2]) depth[$2] = value
			if (value > maximum) maximum = value
		}
		END {print maximum + 0}
	' "$file"
}

root_lifetime_seconds()
{
	local assignment started now
	assignment="$(task_root_assignment_file "$1")"
	[[ -f "$assignment" ]] || { printf '0\n'; return 0; }
	started="$(stat -c %Y "$assignment" 2>/dev/null || printf 0)"
	now="$(epoch_now)"
	[[ "$started" =~ ^[0-9]+$ ]] || started="$now"
	(( now >= started )) || started="$now"
	printf '%s\n' "$((now - started))"
}

root_processed_token_count()
{
	local ledger
	ledger="$(task_root_token_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk -F '\t' 'NR > 1 {total += $7} END {printf "%.0f\n", total + 0}' "$ledger"
}

root_agent_episode_count()
{
	local ledger
	ledger="$(task_root_token_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk 'END {print (NR > 0 ? NR - 1 : 0)}' "$ledger"
}

root_verified_facet_count()
{
	local ledger
	ledger="$(task_criterion_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk -F '\t' 'NR > 1 && ($2 == "PASSED" || $2 == "VERIFIED") && !seen[$1]++ {count++} END {print count + 0}' "$ledger"
}

refresh_project_efficiency_metrics()
{
	local metrics total=0 facets=0 ratio=UNAVAILABLE tmp file
	local -a token_ledgers=() criterion_ledgers=()
	shopt -s nullglob
	token_ledgers=("$(project_dir)/control/progress/$PROJECT-task-"*.tokens.tsv)
	criterion_ledgers=("$(project_dir)/control/progress/$PROJECT-task-"*.criteria.tsv)
	shopt -u nullglob
	if (( ${#token_ledgers[@]} > 0 )); then
		total="$(awk -F '\t' 'FNR>1 {total += $7} END {printf "%.0f\n", total+0}' "${token_ledgers[@]}")"
	fi
	if (( ${#criterion_ledgers[@]} > 0 )); then
		facets="$(awk -F '\t' 'FNR>1 && ($2=="PASSED" || $2=="VERIFIED") && !seen[FILENAME SUBSEP $1]++ {count++} END {print count+0}' "${criterion_ledgers[@]}")"
	fi
	(( facets == 0 )) || ratio=$((total / facets))
	metrics="$(project_efficiency_metrics_file)"
	tmp="$metrics.tmp.$$"
	{
		printf 'project=%s\nupdated_at=%s\n' "$PROJECT" "$(timestamp_utc)"
		printf 'total_processed_tokens=%s\nverified_facets=%s\ntokens_per_verified_facet=%s\n' "$total" "$facets" "$ratio"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$metrics"
}

refresh_root_efficiency_metrics()
{
	local root="$1" baseline metrics total facets episodes base_tokens base_facets base_episodes
	local delta_tokens delta_facets delta_episodes ratio=UNAVAILABLE delta_ratio=UNAVAILABLE tmp
	root="$(task_root_id "$root")"
	baseline="$(task_root_efficiency_baseline_file "$root")"
	metrics="$(task_root_efficiency_metrics_file "$root")"
	total="$(root_processed_token_count "$root")"
	facets="$(root_verified_facet_count "$root")"
	episodes="$(root_agent_episode_count "$root")"
	base_tokens="$total"; base_facets="$facets"; base_episodes="$episodes"
	if [[ -f "$baseline" ]]; then
		base_tokens="$(kv_file_value "$baseline" processed_tokens 2>/dev/null || printf '%s' "$total")"
		base_facets="$(kv_file_value "$baseline" verified_facets 2>/dev/null || printf '%s' "$facets")"
		base_episodes="$(kv_file_value "$baseline" agent_episodes 2>/dev/null || printf '%s' "$episodes")"
	fi
	for value_name in total facets episodes base_tokens base_facets base_episodes; do
		[[ "${!value_name}" =~ ^[0-9]+$ ]] || printf -v "$value_name" 0
	done
	(( total >= base_tokens )) || base_tokens="$total"
	(( facets >= base_facets )) || base_facets="$facets"
	(( episodes >= base_episodes )) || base_episodes="$episodes"
	delta_tokens=$((total - base_tokens))
	delta_facets=$((facets - base_facets))
	delta_episodes=$((episodes - base_episodes))
	(( facets == 0 )) || ratio=$((total / facets))
	(( delta_facets == 0 )) || delta_ratio=$((delta_tokens / delta_facets))
	tmp="$metrics.tmp.$$"
	{
		printf 'task_root=%s\nupdated_at=%s\n' "$root" "$(timestamp_utc)"
		printf 'total_processed_tokens=%s\nverified_facets=%s\nagent_episodes=%s\n' "$total" "$facets" "$episodes"
		printf 'tokens_per_verified_facet=%s\n' "$ratio"
		printf 'boundary_processed_tokens=%s\nboundary_verified_facets=%s\nboundary_agent_episodes=%s\n' "$base_tokens" "$base_facets" "$base_episodes"
		printf 'tokens_since_verified_facet=%s\nepisodes_since_verified_facet=%s\nnewly_verified_facets=%s\n' "$delta_tokens" "$delta_episodes" "$delta_facets"
		printf 'tokens_per_newly_verified_facet=%s\n' "$delta_ratio"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$metrics"
	refresh_project_efficiency_metrics
}

record_root_verified_facet_boundary()
{
	local root="$1" baseline tmp total facets episodes prior_tokens prior_facets delta_tokens delta_facets ratio ledger
	root="$(task_root_id "$root")"
	baseline="$(task_root_efficiency_baseline_file "$root")"
	total="$(root_processed_token_count "$root")"
	facets="$(root_verified_facet_count "$root")"
	episodes="$(root_agent_episode_count "$root")"
	if [[ -f "$baseline" ]]; then
		prior_tokens="$(kv_file_value "$baseline" processed_tokens 2>/dev/null || printf '%s' "$total")"
		prior_facets="$(kv_file_value "$baseline" verified_facets 2>/dev/null || printf '%s' "$facets")"
		if [[ "$prior_tokens" =~ ^[0-9]+$ && "$prior_facets" =~ ^[0-9]+$ ]] && (( facets > prior_facets )); then
			delta_tokens=$((total - prior_tokens)); delta_facets=$((facets - prior_facets)); ratio=$((delta_tokens / delta_facets))
			ledger="$(project_verified_facet_efficiency_ledger_file)"
			if [[ ! -f "$ledger" ]]; then
				printf 'verified_at\ttask_root\tprocessed_tokens\tnewly_verified_facets\ttokens_per_verified_facet\n' > "$ledger"
				chmod 600 "$ledger"
			fi
			printf '%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$root" "$delta_tokens" "$delta_facets" "$ratio" >> "$ledger"
		fi
	fi
	tmp="$baseline.tmp.$$"
	{
		printf 'task_root=%s\nrecorded_at=%s\n' "$root" "$(timestamp_utc)"
		printf 'processed_tokens=%s\n' "$total"
		printf 'verified_facets=%s\n' "$facets"
		printf 'agent_episodes=%s\n' "$episodes"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$baseline"
	refresh_root_efficiency_metrics "$root"
}

evaluate_tokens_without_verified_gain()
{
	local root="$1" baseline total facets episodes base_tokens base_facets base_episodes delta_tokens delta_episodes
	local reason evidence marker
	[[ "$HARNESS_IRREGULARITY_DETECTION_ENABLED" == 1 ]] || return 0
	root="$(task_root_id "$root")"
	baseline="$(task_root_efficiency_baseline_file "$root")"
	if [[ ! -f "$baseline" ]]; then
		# Lazy initialization prevents a deployment from treating historical
		# activity as a fresh incident.
		record_root_verified_facet_boundary "$root"
		return 0
	fi
	total="$(root_processed_token_count "$root")"; facets="$(root_verified_facet_count "$root")"
	episodes="$(root_agent_episode_count "$root")"
	base_tokens="$(kv_file_value "$baseline" processed_tokens 2>/dev/null || printf '%s' "$total")"
	base_facets="$(kv_file_value "$baseline" verified_facets 2>/dev/null || printf '%s' "$facets")"
	base_episodes="$(kv_file_value "$baseline" agent_episodes 2>/dev/null || printf '%s' "$episodes")"
	if (( facets > base_facets )); then
		record_root_verified_facet_boundary "$root"
		return 0
	fi
	delta_tokens=$((total - base_tokens)); delta_episodes=$((episodes - base_episodes))
	refresh_root_efficiency_metrics "$root"
	if (( delta_episodes >= HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET &&
		delta_tokens >= HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET )); then
		reason="$delta_episodes paid agent episodes consumed $delta_tokens processed tokens without verifying a new obligation facet"
		evidence="baseline=$baseline metrics=$(task_root_efficiency_metrics_file "$root")"
		marker="$(mark_root_architecture_reassessment "$root" TOKENS_WITHOUT_VERIFIED_GAIN "$reason" "$evidence")"
		record_irregularity TASK_RESOURCE_ANOMALY TOKENS_WITHOUT_VERIFIED_GAIN "$root" "$root" "$reason" "$evidence" "$marker"
		return 1
	fi
	return 0
}

worker_task_processed_token_count()
{
	local task_id="$1" ledger
	ledger="$(task_root_token_ledger_file "$(task_root_id "$task_id")")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk -F '\t' -v task="$task_id" \
		'NR > 1 && $2 == task && $3 ~ /^worker/ {total += $7} END {printf "%.0f\n", total + 0}' \
		"$ledger"
}

record_root_agent_tokens()
{
	local task_id="$1" role="$2" classification="$3" root thread input output current
	local token_dir thread_key thread_state prior delta ledger tmp class estimated authoritative delta_known
	[[ -f "$classification" ]] || return 0
	root="$(task_root_id "$task_id")"
	class="$(kv_file_value "$classification" classification 2>/dev/null || true)"
	thread="$(kv_file_value "$classification" thread_id 2>/dev/null || true)"
	input="$(kv_file_value "$classification" input_tokens 2>/dev/null || true)"
	output="$(kv_file_value "$classification" output_tokens 2>/dev/null || true)"
	if [[ -z "$thread" || ! "$input" =~ ^[0-9]+$ || ! "$output" =~ ^[0-9]+$ ]]; then
		if [[ "$class" == success ]]; then
			mark_project_integrity_anomaly ACCOUNTING_INCONSISTENCY "$task_id" \
				'successful agent episode has missing or malformed authoritative token usage' \
				"role=$role classification=$classification thread=${thread:--} input=${input:--} output=${output:--}" >/dev/null
		fi
		return 0
	fi
	current=$((input + output))
	estimated="$(kv_file_value "$classification" estimated_processed_tokens 2>/dev/null || printf 0)"
	authoritative="$(kv_file_value "$classification" invocation_processed_delta 2>/dev/null || printf 0)"
	delta_known="$(kv_file_value "$classification" invocation_delta_known 2>/dev/null || printf 0)"
	if [[ "$estimated" =~ ^[0-9]+$ && "$authoritative" =~ ^[0-9]+$ ]] &&
		(( estimated >= HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS &&
		authoritative >= HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS )) &&
		{ (( estimated * 100 > authoritative * HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT )) ||
			(( authoritative * 100 > estimated * HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT )); }; then
		mark_project_integrity_anomaly ACCOUNTING_INCONSISTENCY "$task_id" \
			'estimated and authoritative token accounting differ beyond the configured ratio' \
			"role=$role estimated=$estimated authoritative=$authoritative threshold_percent=$HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT classification=$classification" >/dev/null
	fi
	token_dir="$(project_dir)/control/agent-token-thread-state"
	mkdir -p "$token_dir"
	chmod 700 "$token_dir"
	# Codex usage is cumulative per thread. Key only by thread so alternating
	# manager review/replan roles cannot charge the same cumulative context twice.
	thread_key="$(printf '%s' "$thread" | sha256sum | awk '{print $1}')"
	thread_state="$token_dir/$thread_key.env"
	exec 7>"$(project_dir)/control/agent-token-accounting.lock"
	flock -x 7
	prior=0
	[[ ! -f "$thread_state" ]] || prior="$(kv_file_value "$thread_state" processed_tokens 2>/dev/null || printf 0)"
	[[ "$prior" =~ ^[0-9]+$ ]] || prior=0
	if (( current < prior )); then
		flock -u 7
		mark_project_integrity_anomaly ACCOUNTING_INCONSISTENCY "$task_id" \
			'authoritative cumulative token counter moved backwards' \
			"role=$role thread=$thread prior=$prior current=$current classification=$classification" >/dev/null
		return 0
	fi
	if (( current > prior )); then
		if (( prior == 0 )) && [[ "$role" == manager* ]]; then
			# A persistent manager thread may predate this release or this root.
			# Establish its baseline without charging historical context to the
			# currently active plan item.
			delta=0
		else
			delta=$((current - prior))
		fi
		if [[ "$delta_known" == 1 && "$authoritative" =~ ^[0-9]+$ ]] &&
			! { (( prior == 0 )) && [[ "$role" == manager* ]]; } && (( delta != authoritative )); then
			mark_project_integrity_anomaly ACCOUNTING_INCONSISTENCY "$task_id" \
				'root token-ledger delta disagrees with the invocation classifier delta' \
				"role=$role thread=$thread prior=$prior current=$current ledger_delta=$delta invocation_delta=$authoritative classification=$classification" >/dev/null
		fi
		tmp="$thread_state.tmp.$$"
		{
			printf 'role=%s\n' "$role"
			printf 'thread_id=%s\n' "$thread"
			printf 'processed_tokens=%s\n' "$current"
			printf 'updated_at=%s\n' "$(timestamp_utc)"
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$thread_state"
		if (( delta > 0 )); then
			ledger="$(task_root_token_ledger_file "$root")"
			if [[ ! -f "$ledger" ]]; then
				printf 'recorded_at\ttask_id\trole\tthread_id\tinput_tokens\toutput_tokens\tprocessed_delta\n' > "$ledger"
				chmod 600 "$ledger"
			fi
			printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$task_id" \
				"$role" "$thread" "$input" "$output" "$delta" >> "$ledger"
		fi
	fi
	flock -u 7
	evaluate_tokens_without_verified_gain "$root" || true
}

record_worker_complexity_observation()
{
	local task_id="$1" plan_node="$2" role="$3" model="$4" classification="$5" json="$6"
	local report score predicted_actions predicted_p95 actual usage_source items commands output_bytes max_output source_read_bytes repeated_reads
	local changed_files changed_lines duration class route leaf_type planner_model planner_effort ledger lock metrics header tmp
	[[ -f "$classification" && -f "$json" ]] || return 0
	report="$(decomposition_complexity_report_file)"
	score=0; predicted_actions=0; predicted_p95=0; route=UNKNOWN; leaf_type=UNKNOWN
	if [[ -f "$report" && -n "$plan_node" ]]; then
		IFS=$'\t' read -r route leaf_type score _ _ _ _ _ _ _ _ _ _ predicted_actions _ predicted_p95 _ _ _ < <(
			awk -F '\t' -v node="$plan_node" 'NR>1 && $1==node {for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":"\t"); exit}' "$report"
		) || true
	fi
	[[ -n "$leaf_type" && "$leaf_type" != - ]] || leaf_type="$(project_plan_node_value "$plan_node" leaf_type 2>/dev/null || printf UNKNOWN)"
	[[ -n "$leaf_type" ]] || leaf_type=UNKNOWN
	planner_model="$(decomposition_provenance_value planner_model "$DECOMPOSITION_MODEL" 2>/dev/null || printf '%s' "$DECOMPOSITION_MODEL")"
	planner_effort="$(decomposition_provenance_value planner_reasoning_effort "$DECOMPOSITION_REASONING_EFFORT" 2>/dev/null || printf '%s' "$DECOMPOSITION_REASONING_EFFORT")"
	[[ "$score" =~ ^[0-9]+$ ]] || score=0
	[[ "$predicted_actions" =~ ^[0-9]+$ ]] || predicted_actions=0
	[[ "$predicted_p95" =~ ^[0-9]+$ ]] || predicted_p95=0
	actual="$(kv_file_value "$classification" invocation_processed_delta 2>/dev/null || printf 0)"
	[[ "$actual" =~ ^[0-9]+$ ]] || actual=0
	usage_source=actual
	if (( actual == 0 )); then
		actual="$(kv_file_value "$classification" estimated_processed_tokens 2>/dev/null || printf 0)"
		[[ "$actual" =~ ^[0-9]+$ ]] || actual=0
		usage_source=estimated
	fi
	items="$(kv_file_value "$classification" item_started_count 2>/dev/null || printf 0)"
	changed_files="$(kv_file_value "$classification" changed_file_count 2>/dev/null || printf 0)"
	changed_lines="$(kv_file_value "$classification" changed_line_count 2>/dev/null || printf 0)"
	duration="$(kv_file_value "$classification" invocation_duration_seconds 2>/dev/null || printf 0)"
	class="$(kv_file_value "$classification" classification 2>/dev/null || printf unknown)"
	metrics="$(jq -rs '
		[.[] | select(.type=="item.completed" and .item.type=="command_execution")] as $commands |
		[$commands[] | ((.item.aggregated_output // "")|tostring|length)] as $sizes |
		[$commands[] | select((.item.command // "")|test("(^|[ ;|])(rg|grep|sed|awk|head)([ ;|]|$)")) |
			((.item.aggregated_output // "")|tostring|length)] as $source_sizes |
		[$commands[] | select((.item.command // "")|test("(^|[ ;|])(rg|grep|sed|awk|head)([ ;|]|$)")) | .item.command] as $reads |
		[($commands|length), ($sizes|add // 0), ($sizes|max // 0), ($source_sizes|add // 0),
		 (($reads|length) - ($reads|unique|length))] | @tsv
	' "$json" 2>/dev/null || printf '0\t0\t0\t0\t0')"
	IFS=$'\t' read -r commands output_bytes max_output source_read_bytes repeated_reads <<< "$metrics"
	for value_name in items changed_files changed_lines duration commands output_bytes max_output source_read_bytes repeated_reads; do
		[[ "${!value_name}" =~ ^[0-9]+$ ]] || printf -v "$value_name" 0
	done
	ledger="$(project_dir)/logs/complexity-observations.tsv"
	lock="$(project_dir)/control/complexity-observations.lock"
	exec 6>"$lock"
	flock -x 6
	if [[ ! -f "$ledger" ]]; then
		printf 'recorded_at\tproject\tplan_node\ttask_id\trole\tmodel\tworker_route\tcomplexity_score\tpredicted_actions\tpredicted_p95_tokens\tprocessed_tokens\tusage_source\titems\tcommands\toutput_bytes\tmax_output_bytes\tsource_read_bytes\trepeated_source_reads\tchanged_files\tduration_seconds\tclassification\tchanged_lines\tplanner_model\tplanner_effort\tleaf_type\n' > "$ledger"
		chmod 600 "$ledger"
	else
		header="$(head -n 1 "$ledger")"
		if [[ "$header" != *$'\tplanner_model\tplanner_effort\tleaf_type' ]]; then
			tmp="$ledger.migrate.$$"
			awk -F '\t' -v OFS='\t' -v planner="$planner_model" -v effort="$planner_effort" '
				NR==1 {print $0,"planner_model","planner_effort","leaf_type"; next}
				{print $0,planner,effort,($7==""?"UNKNOWN":$7)}
			' "$ledger" > "$tmp"
			chmod 600 "$tmp"
			mv "$tmp" "$ledger"
		fi
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$(timestamp_utc)" "$PROJECT" "${plan_node:--}" "$task_id" "$role" "$model" "$route" "$score" \
		"$predicted_actions" "$predicted_p95" "$actual" "$usage_source" "$items" "$commands" "$output_bytes" \
		"$max_output" "$source_read_bytes" "$repeated_reads" "$changed_files" "$duration" "$class" "$changed_lines" \
		"$planner_model" "$planner_effort" "$leaf_type" >> "$ledger"
	flock -u 6
}

evaluate_worker_episode_irregularities()
{
	local task_id="$1" ledger output category reason evidence prior
	local -A seen=()
	[[ "$HARNESS_IRREGULARITY_DETECTION_ENABLED" == 1 ]] || return 1
	ledger="$(project_dir)/logs/complexity-observations.tsv"
	output="$(mktemp)"
	if ! python3 "$HARNESS_HOME/tools/irregularity_detector.py" episode --observations "$ledger" \
		--outcomes "$(project_dir)/logs/complexity-outcomes.tsv" \
		--task "$task_id" --regression-percent "$HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT" \
		--min-samples "$HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES" > "$output"; then
		rm -f "$output"
		return 1
	fi
	while IFS=$'\t' read -r category reason evidence; do
		[[ -n "$category" && -z "${seen[$category]:-}" ]] || continue
		seen["$category"]=1
		prior=0
		if [[ -f "$(project_irregularity_ledger_file)" ]]; then
			prior="$(awk -F '\t' -v task="$task_id" -v category="$category" \
				'NR>1 && $3==category && $4==task {count++} END {print count+0}' "$(project_irregularity_ledger_file)")"
		fi
		if (( prior + 1 >= HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT )); then
			mark_task_resource_anomaly "$task_id" "$category" "$reason" "$evidence" >/dev/null
		else
			mark_efficiency_warning "$category" "$task_id" "$reason" "$evidence"
		fi
	done < "$output"
	rm -f "$output"
	task_has_resource_anomaly "$task_id"
}

record_worker_complexity_outcome()
{
	local task_id="$1" outcome="$2" root plan_node replans planner_model planner_effort ledger lock
	[[ "$outcome" =~ ^(ACCEPTED|CHECKPOINTED|REJECTED|BLOCKED|SUPERSEDED)$ ]] || return 0
	root="$(task_root_id "$task_id")"
	plan_node="$(project_plan_item_for_root "$root" 2>/dev/null || true)"
	replans="$(root_total_replan_count "$root" 2>/dev/null || printf 0)"
	[[ "$replans" =~ ^[0-9]+$ ]] || replans=0
	planner_model="$(decomposition_provenance_value planner_model "$DECOMPOSITION_MODEL" 2>/dev/null || printf '%s' "$DECOMPOSITION_MODEL")"
	planner_effort="$(decomposition_provenance_value planner_reasoning_effort "$DECOMPOSITION_REASONING_EFFORT" 2>/dev/null || printf '%s' "$DECOMPOSITION_REASONING_EFFORT")"
	ledger="$(project_dir)/logs/complexity-outcomes.tsv"
	lock="$(project_dir)/control/complexity-observations.lock"
	exec 6>"$lock"
	flock -x 6
	if [[ ! -f "$ledger" ]]; then
		printf 'recorded_at\tproject\tplan_node\ttask_id\toutcome\troot_replans\tplanner_model\tplanner_effort\n' > "$ledger"
		chmod 600 "$ledger"
	fi
	if ! awk -F '\t' -v project="$PROJECT" -v task="$task_id" -v outcome="$outcome" \
		'NR>1 && $2==project && $4==task && $5==outcome {found=1} END{exit found?0:1}' "$ledger"; then
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp_utc)" "$PROJECT" "${plan_node:--}" \
			"$task_id" "$outcome" "$replans" "$planner_model" "$planner_effort" >> "$ledger"
	fi
	flock -u 6
	record_context_closure_outcome "$task_id" "$outcome" "${plan_node:--}"
	refresh_context_closure_feedback
}

refresh_context_closure_feedback()
{
	local dir predictions omissions tmp
	dir="$(project_dir)"
	[[ -f "$HARNESS_HOME/tools/context_closure_metrics.py" ]] || return 0
	predictions="$dir/control/context-closure-predictions.tsv"
	tmp="$predictions.tmp.$$"
	if python3 "$HARNESS_HOME/tools/context_closure_metrics.py" predictions --project "$dir" > "$tmp"; then
		chmod 600 "$tmp"
		mv "$tmp" "$predictions"
	else
		rm -f "$tmp"
	fi
	omissions="$dir/control/context-closure-systematic-omissions.tsv"
	tmp="$omissions.tmp.$$"
	if python3 "$HARNESS_HOME/tools/context_closure_metrics.py" omissions --project "$dir" > "$tmp"; then
		chmod 600 "$tmp"
		mv "$tmp" "$omissions"
	else
		rm -f "$tmp"
	fi
}

record_context_closure_outcome()
{
	local task_id="$1" outcome="$2" plan_node="$3" dir ledger lock summary report closure_manifest closure_status header tmp
	local commands closure_paths used unused missing changed_outside
	dir="$(project_dir)"
	ledger="$dir/logs/context-closure-outcomes.tsv"
	lock="$dir/control/context-closure-outcomes.lock"
	exec 5>"$lock"
	flock -x 5
	if [[ ! -f "$ledger" ]]; then
		printf 'recorded_at\tproject\tplan_node\ttask_id\toutcome\tusage_report\tcommands\tclosure_paths\tused_paths\tunused_candidates\tmissing_candidates\tchanged_outside_closure\tclosure_status\n' > "$ledger"
		chmod 600 "$ledger"
	else
		header="$(head -n 1 "$ledger")"
		if [[ "$header" != *$'\tclosure_status' ]]; then
			tmp="$ledger.migrate.$$"
			awk -F '\t' -v OFS='\t' 'NR==1 {print $0,"closure_status"; next} {print $0,"UNKNOWN"}' "$ledger" > "$tmp"
			chmod 600 "$tmp"
			mv "$tmp" "$ledger"
		fi
	fi
	closure_manifest="$dir/control/context-closures/$(task_base "$task_id")/manifest.env"
	closure_status=UNKNOWN
	if [[ -f "$closure_manifest" ]]; then
		closure_status="$(kv_file_value "$closure_manifest" status 2>/dev/null || true)"
		[[ -n "$closure_status" ]] || closure_status=UNKNOWN
	fi
	shopt -s nullglob
	for summary in "$dir/logs/context-closure-usage-$task_id-"*.env; do
		report="${summary%.env}.tsv"
		[[ -f "$report" ]] || continue
		if awk -F '\t' -v usage="$report" 'NR>1 && $6==usage {found=1} END{exit found?0:1}' "$ledger"; then
			continue
		fi
		commands="$(kv_file_value "$summary" commands 2>/dev/null || printf 0)"
		closure_paths="$(kv_file_value "$summary" closure_paths 2>/dev/null || printf 0)"
		used="$(kv_file_value "$summary" used_paths 2>/dev/null || printf 0)"
		unused="$(kv_file_value "$summary" unused_candidates 2>/dev/null || printf 0)"
		missing="$(kv_file_value "$summary" missing_candidates 2>/dev/null || printf 0)"
		changed_outside="$(kv_file_value "$summary" changed_outside_closure 2>/dev/null || printf 0)"
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$(timestamp_utc)" "$PROJECT" "$plan_node" "$task_id" "$outcome" "$report" \
			"$commands" "$closure_paths" "$used" "$unused" "$missing" "$changed_outside" "$closure_status" >> "$ledger"
	done
	shopt -u nullglob
	flock -u 5
}

root_liveness_epoch_delta()
{
	local root="$1" key="$2" current="$3" epoch baseline
	[[ "$current" =~ ^[0-9]+$ ]] || current=0
	epoch="$(task_root_liveness_epoch_file "$root")"
	# Ordinary context rotation, incident resolution, or active-node repair must
	# never erase history. The sole reset authority is the recorded Luna-only
	# migration from an exhausted broad boundary to mandatory append-only child
	# criteria. The old totals remain in the epoch for audit and status output.
	if [[ -f "$epoch" ]] &&
		[[ "$(kv_file_value "$epoch" authorized_reset 2>/dev/null || true)" == 1 ]] &&
		[[ "$(kv_file_value "$epoch" budget_scope 2>/dev/null || true)" == luna-only-migrated-child-boundary ]] &&
		[[ "$(kv_file_value "$epoch" source 2>/dev/null || true)" == luna-only-policy-migration ]]; then
		baseline="$(kv_file_value "$epoch" "$key" 2>/dev/null || printf 0)"
		[[ "$baseline" =~ ^[0-9]+$ ]] || baseline=0
		(( current >= baseline )) || baseline="$current"
		printf '%s\n' "$((current - baseline))"
	else
		printf '%s\n' "$current"
	fi
}

record_root_liveness_epoch()
{
	local root="$1" source="${2:-explicit-architecture-resolution}" epoch tmp
	epoch="$(task_root_liveness_epoch_file "$root")"
	tmp="$epoch.tmp.$$"
	{
		if [[ "$source" == luna-only-policy-migration ]]; then
			printf 'snapshot_only=0\n'
			printf 'authorized_reset=1\n'
			printf 'budget_scope=luna-only-migrated-child-boundary\n'
		else
			printf 'snapshot_only=1\n'
			printf 'authorized_reset=0\n'
			printf 'budget_scope=lifetime-root-acceptance-boundary\n'
		fi
		printf 'reviewed_attempts=%s\n' "$(root_reviewed_attempt_count "$root")"
		printf 'criterionless_reviews=%s\n' "$(root_reviews_without_criterion_completion "$root")"
		printf 'total_replans=%s\n' "$(root_total_replan_count "$root")"
		printf 'lifetime_seconds=%s\n' "$(root_lifetime_seconds "$root")"
		printf 'processed_tokens=%s\n' "$(root_processed_token_count "$root")"
		printf 'source=%s\n' "$source"
		printf 'started_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$epoch"
}

root_liveness_violation_reason()
{
	local root="$1" reviews criterionless_reviews replans lifetime tokens
	reviews="$(root_liveness_epoch_delta "$root" reviewed_attempts "$(root_reviewed_attempt_count "$root")")"
	criterionless_reviews="$(root_liveness_epoch_delta "$root" criterionless_reviews "$(root_reviews_without_criterion_completion "$root")")"
	replans="$(root_liveness_epoch_delta "$root" total_replans "$(root_total_replan_count "$root")")"
	lifetime="$(root_liveness_epoch_delta "$root" lifetime_seconds "$(root_lifetime_seconds "$root")")"
	tokens="$(root_liveness_epoch_delta "$root" processed_tokens "$(root_processed_token_count "$root")")"
	if (( criterionless_reviews >= HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION )); then
		printf 'NO_CRITERION_PROGRESS: reviews without a completed root criterion reached the monotonic limit (%s/%s)' "$criterionless_reviews" "$HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION"
	elif (( reviews >= HARNESS_MAX_TOTAL_ROOT_REVIEWS )); then
		printf 'TOTAL_ROOT_REVIEWS: monotonic reviewed-result budget reached (%s/%s)' "$reviews" "$HARNESS_MAX_TOTAL_ROOT_REVIEWS"
	elif (( replans >= HARNESS_MAX_TOTAL_ROOT_REPLANS )); then
		printf 'TOTAL_ROOT_REPLANS: monotonic automatic-replan budget reached (%s/%s)' "$replans" "$HARNESS_MAX_TOTAL_ROOT_REPLANS"
	elif (( lifetime >= HARNESS_MAX_ROOT_LIFETIME_SECONDS )); then
		printf 'ROOT_LIFETIME: active root lifetime budget reached (%ss/%ss)' "$lifetime" "$HARNESS_MAX_ROOT_LIFETIME_SECONDS"
	elif (( tokens >= HARNESS_MAX_ROOT_PROCESSED_TOKENS )); then
		printf 'ROOT_TOKENS: processed-token budget reached (%s/%s)' "$tokens" "$HARNESS_MAX_ROOT_PROCESSED_TOKENS"
	else
		return 1
	fi
}

mark_root_architecture_reassessment()
{
	local task_id="$1" category="$2" reason="$3" evidence="${4:--}"
	local root marker tmp alarm created=0 pending_replan pending_trigger pending_trigger_task
	local pending_blocker_class pending_remediation_scope pending_context_paths
	root="$(task_root_id "$task_id")"
	marker="$(task_root_architecture_reassessment_file "$root")"
	pending_replan="$(task_root_replan_file "$root")"
	pending_trigger=""
	pending_trigger_task=""
	pending_blocker_class=""
	pending_remediation_scope=""
	pending_context_paths=""
	if [[ -f "$pending_replan" ]]; then
		pending_trigger="$(metadata_value "$pending_replan" Trigger-Outcome)"
		pending_trigger_task="$(metadata_value "$pending_replan" Triggered-By)"
		pending_blocker_class="$(metadata_value "$pending_replan" Blocker-Class)"
		pending_remediation_scope="$(metadata_value "$pending_replan" Remediation-Scope)"
		pending_context_paths="$(metadata_value "$pending_replan" Context-Paths)"
	fi
	if [[ ! -f "$marker" ]]; then
		tmp="$marker.tmp.$$"
		{
			printf '# Architecture Reassessment Required\n\n'
			printf 'Project: %s\n\n' "$PROJECT"
			printf 'Task-Root: %s\n\n' "$root"
			printf 'Triggered-By: %s\n\n' "$task_id"
			printf 'Category: %s\n\n' "$category"
			printf 'Paused-At: %s\n\n' "$(timestamp_utc)"
			printf 'Reason: %s\n\n' "$reason"
			printf 'Evidence: %s\n\n' "$evidence"
			if [[ -n "$pending_trigger" ]]; then
				printf 'Pending-Replan-Trigger: %s\n' "$pending_trigger"
				printf 'Pending-Replan-Triggered-By: %s\n' "${pending_trigger_task:-$task_id}"
				[[ -z "$pending_blocker_class" ]] ||
					printf 'Pending-Replan-Blocker-Class: %s\n' "$pending_blocker_class"
				[[ -z "$pending_remediation_scope" ]] ||
					printf 'Pending-Replan-Remediation-Scope: %s\n' "$pending_remediation_scope"
				[[ -z "$pending_context_paths" ]] ||
					printf 'Pending-Replan-Context-Paths: %s\n' "$pending_context_paths"
				printf '\n'
			fi
			printf 'Total-Root-Reviews: %s\n' "$(root_reviewed_attempt_count "$root")"
			printf 'Reviews-Without-Criterion: %s\n' "$(root_reviews_without_criterion_completion "$root")"
			printf 'Total-Root-Replans: %s\n' "$(root_total_replan_count "$root")"
			printf 'Liveness-Budget-Scope: LIFETIME_ROOT_ACCEPTANCE_BOUNDARY\n'
			printf 'Child-Criteria: %s\n' "$(root_child_criterion_count "$root")"
			printf 'Criterion-Depth: %s\n' "$(root_criterion_max_depth "$root")"
			printf 'Root-Lifetime-Seconds: %s\n' "$(root_lifetime_seconds "$root")"
			printf 'Root-Processed-Tokens: %s\n\n' "$(root_processed_token_count "$root")"
			printf 'No further worker, manager-review, or automatic-replan task may launch for this root. Verified source, commits, checkpoints, and diagnostic evidence are preserved. Resolve the governing architecture or dependency authority, then use harness-resolve-architecture-reassessment with an explicit resolution record.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$marker"
		created=1
	fi
	rm -f "$(task_root_replan_file "$root")" "$(task_root_replanning_file "$root")"
	clear_worker_thread_for_root "$root" architecture-reassessment
	if (( created == 1 )); then
		alarm="$(project_dir)/logs/root-liveness-alarms.log"
		printf '%s\tproject=%s\troot=%s\ttrigger=%s\tcategory=%s\treason=%q\tevidence=%q\n' \
			"$(timestamp_utc)" "$PROJECT" "$root" "$task_id" "$category" "$reason" "$evidence" >> "$alarm"
		chmod 600 "$alarm"
		log_event "ARCHITECTURE_REASSESSMENT_REQUIRED root=$root trigger=$task_id category=$category reason=$(printf '%q' "$reason") marker=$marker"
	fi
	printf '%s\n' "$marker"
}

mark_root_token_usage_anomaly()
{
	local task_id="$1" reason="$2" evidence="${3:--}"
	local root marker tmp alarm created=0 plan_node plan_status planner_model planner_effort
	local observed_task_tokens observed_root_tokens invocation_tokens estimated_tokens reported_task_tokens
	local reported_root_tokens task_token_source root_token_source
	root="$(task_root_id "$task_id")"
	plan_node="$(project_plan_item_for_root "$root" 2>/dev/null || printf '-')"
	plan_status=""
	if [[ -n "$plan_node" && "$plan_node" != - ]]; then
		plan_status="$(project_plan_item_status "$plan_node" 2>/dev/null || true)"
	fi
	# A review invocation may finish after a concurrent review has already
	# accepted this root. Its usage evidence remains in JSONL/classification
	# logs, but it must not resurrect a pause for a completed DAG node.
	if [[ "$plan_status" == COMPLETE ]]; then
		log_event "TOKEN_USAGE_ANOMALY_SUPERSEDED_BY_ACCEPTANCE root=$root trigger=$task_id plan_node=$plan_node reason=$(printf '%q' "$reason") evidence=$(printf '%q' "$evidence")"
		return 0
	fi
	planner_model="$(decomposition_provenance_value planner_model "$DECOMPOSITION_MODEL" 2>/dev/null || printf '%s' "$DECOMPOSITION_MODEL")"
	planner_effort="$(decomposition_provenance_value planner_reasoning_effort "$DECOMPOSITION_REASONING_EFFORT" 2>/dev/null || printf '%s' "$DECOMPOSITION_REASONING_EFFORT")"
	observed_task_tokens="$(worker_task_processed_token_count "$task_id")"
	observed_root_tokens="$(root_processed_token_count "$root")"
	estimated_tokens="$(grep -oE 'estimated_processed_tokens=[0-9]+' <<< "$evidence" | tail -n 1 | cut -d= -f2 || true)"
	invocation_tokens="$(grep -oE 'invocation_processed_delta=[0-9]+' <<< "$evidence" | tail -n 1 | cut -d= -f2 || true)"
	[[ "$observed_task_tokens" =~ ^[0-9]+$ ]] || observed_task_tokens=0
	[[ "$observed_root_tokens" =~ ^[0-9]+$ ]] || observed_root_tokens=0
	[[ "$estimated_tokens" =~ ^[0-9]+$ ]] || estimated_tokens=0
	[[ "$invocation_tokens" =~ ^[0-9]+$ ]] || invocation_tokens=0
	reported_task_tokens="$observed_task_tokens"
	reported_root_tokens="$observed_root_tokens"
	task_token_source=provider-ledger
	root_token_source=provider-ledger
	if (( reported_task_tokens == 0 && invocation_tokens > 0 )); then
		reported_task_tokens="$invocation_tokens"
		reported_root_tokens=$((reported_root_tokens + invocation_tokens))
		task_token_source=provider-current-invocation
		root_token_source=provider-ledger-plus-current-invocation
	elif (( reported_task_tokens == 0 && estimated_tokens > 0 )); then
		reported_task_tokens="$estimated_tokens"
		reported_root_tokens=$((reported_root_tokens + estimated_tokens))
		task_token_source=estimated-current-invocation
		root_token_source=provider-ledger-plus-current-estimate
	fi
	marker="$(task_root_token_usage_anomaly_file "$root")"
	if [[ ! -f "$marker" ]]; then
		tmp="$marker.tmp.$$"
		{
			printf '# Token Usage Anomaly\n\n'
			printf 'Project: %s\n\n' "$PROJECT"
			printf 'Task-Root: %s\n\n' "$root"
			printf 'Triggered-By: %s\n\n' "$task_id"
			printf 'Plan-Node: %s\n\n' "${plan_node:--}"
			printf 'Decomposition-Planner: %s (%s)\n\n' "$planner_model" "$planner_effort"
			printf 'Paused-At: %s\n\n' "$(timestamp_utc)"
			printf 'Reason: %s\n\n' "$reason"
			printf 'Evidence: %s\n\n' "$evidence"
			printf 'Worker-Task-Processed-Tokens: %s\n' "$reported_task_tokens"
			printf 'Worker-Task-Token-Source: %s\n' "$task_token_source"
			printf 'Worker-Task-Token-Limit: %s\n' "$HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS"
			printf 'Root-Processed-Tokens: %s\n' "$reported_root_tokens"
			printf 'Root-Token-Source: %s\n\n' "$root_token_source"
			printf 'No further worker, manager-review, or automatic-replan task may launch for this root. Source changes, commits, receipts, JSONL, and verified checkpoints are preserved. Inspect the offending episode and record a corrective resolution with harness-resolve-token-usage-anomaly before restarting work.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$marker"
		created=1
	fi
	# Close the opposite race ordering: acceptance may have committed while the
	# marker above was being assembled. Re-check after publication; otherwise a
	# late alarm can leave an already-complete project globally paused.
	plan_status=""
	if [[ -n "$plan_node" && "$plan_node" != - ]]; then
		plan_status="$(project_plan_item_status "$plan_node" 2>/dev/null || true)"
	fi
	if [[ "$plan_status" == COMPLETE ]]; then
		archive_superseded_root_token_usage_anomaly "$root" "$task_id" post-publication >/dev/null
		return 0
	fi
	# Preserve the durable needs-replan transaction.  The anomaly marker already
	# suppresses every agent launch, and deleting the recovery intent here turns
	# an explicitly paused replan into an unrelated planning gap after operator
	# resolution.  Only the in-flight PID marker is stale once this episode ends.
	rm -f "$(task_root_replanning_file "$root")"
	clear_worker_thread_for_root "$root" token-usage-anomaly
	if (( created == 1 )); then
		alarm="$(project_dir)/logs/token-usage-alarms.log"
		printf '%s\tproject=%s\troot=%s\ttask=%s\tplan_node=%s\tplanner_model=%s\tplanner_effort=%s\treason=%q\tevidence=%q\tmarker=%s\n' \
			"$(timestamp_utc)" "$PROJECT" "$root" "$task_id" "${plan_node:--}" "$planner_model" "$planner_effort" "$reason" "$evidence" "$marker" >> "$alarm"
		chmod 600 "$alarm"
		log_event "TOKEN_USAGE_ANOMALY root=$root trigger=$task_id plan_node=${plan_node:--} planner_model=$planner_model planner_effort=$planner_effort reason=$(printf '%q' "$reason") evidence=$(printf '%q' "$evidence") marker=$marker"
	fi
	printf '%s\n' "$marker"
}

archive_superseded_root_token_usage_anomaly()
{
	local root="$1" trigger="${2:--}" ordering="${3:-acceptance}"
	local marker archive_dir archive stamp
	marker="$(task_root_token_usage_anomaly_file "$root")"
	[[ -f "$marker" ]] || return 0
	archive_dir="$(project_dir)/archive/token-usage-anomalies"
	mkdir -p "$archive_dir"
	chmod 700 "$archive_dir"
	stamp="$(timestamp_compact_utc)"
	archive="$archive_dir/$PROJECT-task-$root.$stamp.superseded-by-acceptance.md"
	while [[ -e "$archive" ]]; do
		archive="$archive_dir/$PROJECT-task-$root.$stamp.$$.superseded-by-acceptance.md"
	done
	if mv "$marker" "$archive" 2>/dev/null; then
		chmod 600 "$archive"
		log_event "TOKEN_USAGE_ANOMALY_SUPERSEDED_BY_ACCEPTANCE root=$root trigger=$trigger ordering=$ordering archive=$archive"
		printf '%s\n' "$archive"
	fi
}

migrate_legacy_token_limit_human_markers()
{
	local human name root trigger reason archive_dir archive token_marker migrated=0 nullglob_was_set=0
	shopt -q nullglob && nullglob_was_set=1
	shopt -s nullglob
	for human in "$(project_dir)/control/progress/$PROJECT-task-"*.needs-human.md; do
		[[ -f "$human" ]] || continue
		reason="$(awk '/^Reason: / {sub(/^Reason: /, ""); print; exit}' "$human")"
		case "$reason" in
			"agent invocation resource circuit breaker: processed-token delta exceeded ("*) ;;
			*) continue ;;
		esac
		name="${human##*/}"
		root="${name#${PROJECT}-task-}"
		root="${root%.needs-human.md}"
		trigger="$(awk -F': ' '$1 == "Triggered-By" {print $2; exit}' "$human")"
		[[ -n "$trigger" ]] || trigger="$root"
		archive_dir="$(project_dir)/archive/token-usage-anomalies"
		mkdir -p "$archive_dir"
		chmod 700 "$archive_dir"
		archive="$archive_dir/$PROJECT-task-$root.legacy-needs-human.md"
		if [[ -f "$archive" ]] && ! cmp -s "$human" "$archive"; then
			archive="$archive_dir/$PROJECT-task-$root.$(timestamp_compact_utc).legacy-needs-human.md"
		fi
		[[ -f "$archive" ]] || install -m 600 "$human" "$archive"
		token_marker="$(task_root_token_usage_anomaly_file "$root")"
		if [[ ! -f "$token_marker" ]]; then
			mark_root_token_usage_anomaly "$trigger" "$reason" \
				"migrated_from=$archive legacy_state=NEEDS_HUMAN" >/dev/null
		fi
		rm -f "$human"
		log_event "LEGACY_TOKEN_LIMIT_MARKER_MIGRATED root=$root trigger=$trigger source=$human archive=$archive marker=$token_marker"
		migrated=$((migrated + 1))
	done
	(( nullglob_was_set == 1 )) || shopt -u nullglob
	printf '%s\n' "$migrated"
}

enforce_root_liveness_or_reassess()
{
	local task_id="$1" reason category
	if reason="$(root_liveness_violation_reason "$(task_root_id "$task_id")")"; then
		category="${reason%%:*}"
		mark_root_architecture_reassessment "$task_id" "$category" "${reason#*: }" \
			'monotonic plan-item liveness budget; local checkpoints do not reset this limit' >/dev/null
		return 1
	fi
	return 0
}

root_reviewed_attempts_since_replan()
{
	local root="$1" baseline_file baseline total
	baseline_file="$(task_convergence_baseline_file "$root")"
	baseline=0
	[[ ! -f "$baseline_file" ]] || baseline="$(kv_file_value "$baseline_file" reviewed_attempts 2>/dev/null || printf 0)"
	[[ "$baseline" =~ ^[0-9]+$ ]] || baseline=0
	total="$(root_reviewed_attempt_count "$root")"
	(( total >= baseline )) || baseline=0
	printf '%s\n' "$((total - baseline))"
}

root_zero_gain_streak()
{
	local history baseline_file baseline
	history="$(task_progress_history_file "$1")"
	[[ -f "$history" ]] || { printf '0\n'; return 0; }
	baseline_file="$(task_convergence_baseline_file "$1")"
	baseline=0
	[[ ! -f "$baseline_file" ]] || baseline="$(kv_file_value "$baseline_file" history_rows 2>/dev/null || printf 0)"
	[[ "$baseline" =~ ^[0-9]+$ ]] || baseline=0
	awk -F '\t' -v baseline="$baseline" '
		NR > 1 && NR > baseline + 1 {
			decision[++n] = $3
			gain[n] = $5
		}
		END {
			for (i = n; i > 0; i--) {
				# A committed checkpoint necessarily records a new stable
				# criterion or increment. Treat that evidence-backed outcome as
				# gain even when legacy percentage progress is pinned at 99%.
				if (gain[i] != 0 || decision[i] == "CHECKPOINT")
					break
				count++
			}
			print count + 0
		}
	' "$history"
}

root_checkpoint_without_criterion_streak()
{
	local ledger baseline_file baseline
	ledger="$(task_checkpoint_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	baseline_file="$(task_convergence_baseline_file "$1")"
	baseline=0
	[[ ! -f "$baseline_file" ]] || baseline="$(kv_file_value "$baseline_file" checkpoint_rows 2>/dev/null || printf 0)"
	[[ "$baseline" =~ ^[0-9]+$ ]] || baseline=0
	awk -F '\t' -v baseline="$baseline" 'NR > 1 && NR > baseline + 1 {criteria[++n] = $3} END {for (i = n; i > 0 && criteria[i] == 0; i--) count++; print count + 0}' "$ledger"
}

root_reviews_without_criterion_completion()
{
	local root="$1" checkpoint_ledger history last_criterion_task
	checkpoint_ledger="$(task_checkpoint_ledger_file "$root")"
	history="$(task_progress_history_file "$root")"
	[[ -f "$history" ]] || { printf '0\n'; return 0; }
	last_criterion_task=""
	if [[ -f "$checkpoint_ledger" ]]; then
		last_criterion_task="$(awk -F '\t' 'NR > 1 && $3 + 0 > 0 {task=$2} END {print task}' "$checkpoint_ledger")"
	fi
	awk -F '\t' -v completed="$last_criterion_task" '
		NR > 1 {
			if (completed != "" && $2 == completed) count=0
			else count++
		}
		END {print count + 0}
	' "$history"
}

record_root_convergence_baseline()
{
	local root="$1" baseline history checkpoint_ledger history_rows=0 checkpoint_rows=0 tmp
	baseline="$(task_convergence_baseline_file "$root")"
	history="$(task_progress_history_file "$root")"
	checkpoint_ledger="$(task_checkpoint_ledger_file "$root")"
	[[ ! -f "$history" ]] || history_rows="$(( $(wc -l < "$history") - 1 ))"
	[[ ! -f "$checkpoint_ledger" ]] || checkpoint_rows="$(( $(wc -l < "$checkpoint_ledger") - 1 ))"
	(( history_rows >= 0 )) || history_rows=0
	(( checkpoint_rows >= 0 )) || checkpoint_rows=0
	tmp="$baseline.tmp.$$"
	{
		printf 'reviewed_attempts=%s\n' "$(root_reviewed_attempt_count "$root")"
		printf 'history_rows=%s\n' "$history_rows"
		printf 'checkpoint_rows=%s\n' "$checkpoint_rows"
		printf 'resumed_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$baseline"
}

root_auto_replans_without_verified_gain()
{
	local root="$1" ledger current baseline_file baseline=0
	local replanned_at recorded_verified row=0 count=0
	local -a verified_counts=()
	ledger="$(task_replan_ledger_file "$root")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	current="$(task_verified_item_count "$root")"
	baseline_file="$(task_replan_baseline_file "$root")"
	[[ ! -f "$baseline_file" ]] ||
		baseline="$(kv_file_value "$baseline_file" replan_rows 2>/dev/null || printf 0)"
	[[ "$baseline" =~ ^[0-9]+$ ]] || baseline=0
	while IFS=$'\t' read -r replanned_at _ _ _ _ _ _ _ _ recorded_verified _; do
		row=$((row + 1))
		(( row > baseline )) || continue
		if [[ ! "$recorded_verified" =~ ^[0-9]+$ ]]; then
			# Version-1 ledgers recorded only completed root criteria. Recover
			# their durable-gain baseline from the timestamped item ledger.
			recorded_verified="$(task_verified_item_count_at "$root" "$replanned_at")"
		fi
		verified_counts+=("$recorded_verified")
	done < <(tail -n +2 "$ledger")
	for (( row = ${#verified_counts[@]} - 1; row >= 0; row-- )); do
		[[ "${verified_counts[row]}" == "$current" ]] || break
		count=$((count + 1))
	done
	printf '%s\n' "$count"
}

evaluate_root_state_oscillation()
{
	local task_id="$1" target="${2:-}" strategy_fingerprint="${3:-}" blocker_fingerprint="${4:-}"
	local verified="${5:-}" root ledger count reason evidence marker
	[[ "$HARNESS_IRREGULARITY_DETECTION_ENABLED" == 1 ]] || return 0
	root="$(task_root_id "$task_id")"
	ledger="$(task_replan_ledger_file "$root")"
	[[ -f "$ledger" ]] || return 0
	[[ -n "$target" ]] || target="$(awk -F '\t' 'END {print $4}' "$ledger")"
	[[ -n "$strategy_fingerprint" ]] || strategy_fingerprint="$(awk -F '\t' 'END {print $7}' "$ledger")"
	[[ -n "$blocker_fingerprint" ]] || blocker_fingerprint="$(awk -F '\t' 'END {print $8}' "$ledger")"
	[[ -n "$verified" ]] || verified="$(task_verified_item_count "$root")"
	# Oscillation is a consecutive unchanged-state condition, not a count of
	# every historical attempt at the same criterion.  Include the candidate
	# publication, then walk backward only while its complete material state
	# (strategy, blocker, and verified evidence) remains identical.
	count="$(awk -F '\t' -v target="$target" -v strategy="$strategy_fingerprint" \
		-v blocker="$blocker_fingerprint" -v verified="$verified" '
		NR>1 {target_by_row[NR]=$4; strategy_by_row[NR]=$7; blocker_by_row[NR]=$8; verified_by_row[NR]=$10; last=NR}
		END {
			count=1
			for (row=last; row>1; row--) {
				if (target_by_row[row]!=target || strategy_by_row[row]!=strategy ||
				    blocker_by_row[row]!=blocker || verified_by_row[row]!=verified) break
				count++
			}
			print count
		}' "$ledger")"
	if (( count >= HARNESS_MAX_STATE_OSCILLATIONS )); then
		reason="root repeated the same material recovery state $count consecutive times without new verified evidence"
		evidence="target=$target strategy_fingerprint=$strategy_fingerprint blocker_fingerprint=$blocker_fingerprint verified_items=$verified ledger=$ledger limit=$HARNESS_MAX_STATE_OSCILLATIONS"
		marker="$(mark_root_architecture_reassessment "$task_id" STATE_OSCILLATION "$reason" "$evidence")"
		record_irregularity TASK_RESOURCE_ANOMALY STATE_OSCILLATION "$task_id" "$root" "$reason" "$evidence" "$marker"
		return 1
	fi
	return 0
}

# Compatibility wrapper for integrations written against the original name.
# Its semantics intentionally follow durable verified gain now.
root_auto_replans_without_criterion()
{
	root_auto_replans_without_verified_gain "$1"
}

root_last_auto_replan_verified_item_count()
{
	local root="$1" ledger replanned_at recorded_verified
	ledger="$(task_replan_ledger_file "$root")"
	[[ -f "$ledger" ]] || return 1
	IFS=$'\t' read -r replanned_at _ _ _ _ _ _ _ _ recorded_verified _ \
		< <(tail -n 1 "$ledger")
	[[ -n "$replanned_at" && "$replanned_at" != replanned_at ]] || return 1
	if [[ ! "$recorded_verified" =~ ^[0-9]+$ ]]; then
		recorded_verified="$(task_verified_item_count_at "$root" "$replanned_at")"
	fi
	printf '%s\n' "$recorded_verified"
}

root_verified_gain_since_last_auto_replan()
{
	local root="$1" current previous
	current="$(task_verified_item_count "$root")"
	previous="$(root_last_auto_replan_verified_item_count "$root" 2>/dev/null || true)"
	if [[ ! "$previous" =~ ^[0-9]+$ ]]; then
		printf '0\n'
		return 0
	fi
	(( current >= previous )) || { printf '0\n'; return 0; }
	printf '%s\n' "$((current - previous))"
}

root_same_blocker_without_verified_gain()
{
	local root="$1" blocker="$2" last_blocker gain
	[[ -n "$blocker" && "$blocker" != "-" ]] || return 1
	last_blocker="$(root_last_auto_replan_blocker "$root" 2>/dev/null || true)"
	[[ "$blocker" == "$last_blocker" ]] || return 1
	gain="$(root_verified_gain_since_last_auto_replan "$root")"
	[[ "$gain" == 0 ]]
}

record_root_replan_baseline()
{
	local root="$1" ledger baseline rows=0 tmp
	ledger="$(task_replan_ledger_file "$root")"
	baseline="$(task_replan_baseline_file "$root")"
	[[ ! -f "$ledger" ]] || rows="$(( $(wc -l < "$ledger") - 1 ))"
	(( rows >= 0 )) || rows=0
	tmp="$baseline.tmp.$$"
	{
		printf 'replan_rows=%s\n' "$rows"
		printf 'passed_criteria=%s\n' "$(task_passed_declared_criterion_count "$root")"
		printf 'verified_items=%s\n' "$(task_verified_item_count "$root")"
		printf 'reset_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$baseline"
}

root_last_auto_replan_blocker()
{
	local ledger
	ledger="$(task_replan_ledger_file "$1")"
	[[ -f "$ledger" ]] || return 1
	awk -F '\t' 'NR > 1 {value=$8} END {if (value != "" && value != "-") print value}' "$ledger"
}

ensure_root_replan_ledger_schema()
{
	local root="$1" ledger header tmp existing_header=""
	local replanned_at task_id trigger_task target_criterion strategy_id change_type
	local strategy_fingerprint blocker_fingerprint passed_criterion_count verified_item_count extra
	ledger="$(task_replan_ledger_file "$root")"
	header=$'replanned_at\ttask_id\ttrigger_task\ttarget_criterion\tstrategy_id\tchange_type\tstrategy_fingerprint\tblocker_fingerprint\tpassed_criterion_count\tverified_item_count'
	if [[ ! -f "$ledger" ]]; then
		printf '%s\n' "$header" > "$ledger"
		chmod 600 "$ledger"
		return 0
	fi
	if IFS= read -r existing_header < "$ledger" && [[ "$existing_header" == "$header" ]]; then
		return 0
	fi
	[[ "$existing_header" == $'replanned_at\ttask_id\ttrigger_task\ttarget_criterion\tstrategy_id\tchange_type\tstrategy_fingerprint\tblocker_fingerprint\tpassed_criterion_count' ]] ||
		die "unsupported automatic replan ledger schema: $ledger"
	tmp="$ledger.tmp.$$"
	printf '%s\n' "$header" > "$tmp"
	while IFS=$'\t' read -r replanned_at task_id trigger_task target_criterion strategy_id change_type \
		strategy_fingerprint blocker_fingerprint passed_criterion_count extra; do
		[[ -z "$extra" ]] || die "malformed automatic replan ledger row: $ledger"
		verified_item_count="$(task_verified_item_count_at "$root" "$replanned_at")"
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$replanned_at" "$task_id" "$trigger_task" "$target_criterion" "$strategy_id" \
			"$change_type" "$strategy_fingerprint" "$blocker_fingerprint" \
			"$passed_criterion_count" "$verified_item_count" >> "$tmp"
	done < <(tail -n +2 "$ledger")
	chmod 600 "$tmp"
	mv "$tmp" "$ledger"
}

ensure_root_manager_remediation_ledger_schema()
{
	local root="$1" ledger header existing_header=""
	ledger="$(task_manager_remediation_ledger_file "$root")"
	header=$'recorded_at\ttask_id\ttrigger_task\ttarget_criterion\tblocker_fingerprint\tblocker_class\tremediation_scope\tmanager_model'
	if [[ ! -f "$ledger" ]]; then
		printf '%s\n' "$header" > "$ledger"
		chmod 600 "$ledger"
		return 0
	fi
	IFS= read -r existing_header < "$ledger" || true
	[[ "$existing_header" == "$header" ]] ||
		die "unsupported manager remediation ledger schema: $ledger"
}

ensure_root_hard_block_ledger_schema()
{
	local root="$1" ledger header existing_header=""
	ledger="$(task_hard_block_ledger_file "$root")"
	header=$'recorded_at\ttask_id\ttask_root\tblocker_class\tdisposition\tremediation_scope\treason'
	if [[ ! -f "$ledger" ]]; then
		printf '%s\n' "$header" > "$ledger"
		chmod 600 "$ledger"
		return 0
	fi
	IFS= read -r existing_header < "$ledger" || true
	[[ "$existing_header" == "$header" ]] ||
		die "unsupported hard-block ledger schema: $ledger"
}

record_root_hard_block()
{
	local task_id="$1" blocker_class="$2" disposition="$3"
	local remediation_scope="${4:--}" reason="${5:--}" root ledger
	root="$(task_root_id "$task_id")"
	[[ "$blocker_class" =~ ^(LOCAL_CODE_PREREQUISITE|LOCAL_BUILD_PREREQUISITE|LOCAL_INTEGRATION_PREREQUISITE|LOCAL_SCOPE_PREREQUISITE|HUMAN_AUTHORIZATION|HUMAN_SECRET|HUMAN_EXTERNAL_STATE|HUMAN_PRODUCT_SPECIFICATION)$ ]] ||
		die "invalid hard-block class: $blocker_class"
	[[ "$disposition" =~ ^(MANAGER_REMEDIATION|NEEDS_HUMAN)$ ]] ||
		die "invalid hard-block disposition: $disposition"
	[[ "$remediation_scope" != *$'\t'* && "$remediation_scope" != *$'\n'* && "$remediation_scope" != *$'\r'* ]] ||
		die 'hard-block remediation scope must be one tab-free line'
	[[ "$reason" != *$'\t'* && "$reason" != *$'\n'* && "$reason" != *$'\r'* ]] ||
		die 'hard-block reason must be one tab-free line'
	ensure_root_hard_block_ledger_schema "$root"
	ledger="$(task_hard_block_ledger_file "$root")"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$(timestamp_utc)" "$task_id" "$root" "$blocker_class" "$disposition" \
		"${remediation_scope:--}" "${reason:--}" >> "$ledger"
}

hard_block_class_is_local()
{
	[[ "$1" =~ ^(LOCAL_CODE_PREREQUISITE|LOCAL_BUILD_PREREQUISITE|LOCAL_INTEGRATION_PREREQUISITE|LOCAL_SCOPE_PREREQUISITE)$ ]]
}

hard_block_class_is_human()
{
	[[ "$1" =~ ^(HUMAN_AUTHORIZATION|HUMAN_SECRET|HUMAN_EXTERNAL_STATE|HUMAN_PRODUCT_SPECIFICATION)$ ]]
}

root_manager_remediation_count()
{
	local ledger rows
	ledger="$(task_manager_remediation_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	rows="$(( $(wc -l < "$ledger") - 1 ))"
	(( rows >= 0 )) || rows=0
	printf '%s\n' "$rows"
}

root_manager_remediation_unique_blocker_count()
{
	local ledger
	ledger="$(task_manager_remediation_ledger_file "$1")"
	[[ -f "$ledger" ]] || { printf '0\n'; return 0; }
	awk -F '\t' 'NR > 1 && $5 != "" && $5 != "-" {seen[$5]=1} END {for (item in seen) count++; print count + 0}' "$ledger"
}

assignment_is_manager_remediation()
{
	local file="$1"
	[[ -f "$file" ]] &&
		[[ "$(metadata_value "$file" Manager-Remediation)" == 1 ]]
}

mark_root_needs_human()
{
	local root="$1" trigger_task="$2" reason="$3"
	local blocker_class="${4:-}" human_evidence="${5:-}" marker tmp
	root="$(task_root_id "$root")"
	marker="$(task_root_human_file "$root")"
	if [[ ! -f "$marker" ]]; then
		tmp="$marker.tmp.$$"
		{
			printf '# Root Task Needs Human Intervention\n\n'
			printf 'Project: %s\n\n' "$PROJECT"
			printf 'Task-Root: %s\n\n' "$root"
			printf 'Triggered-By: %s\n\n' "$trigger_task"
			printf 'Paused-At: %s\n\n' "$(timestamp_utc)"
			printf 'Progress-Percent: %s%%\n\n' "$(task_progress_percent "$root")"
			printf 'Reason: %s\n\n' "$reason"
			if [[ -n "$blocker_class" ]]; then
				printf 'Blocker-Class: %s\n\n' "$blocker_class"
			fi
			if [[ -n "$human_evidence" ]]; then
				printf 'Human-Dependency-Evidence: %s\n\n' "$human_evidence"
			fi
			printf 'Verified checkpoints, criterion evidence, review history, and repository changes are preserved. An operator must inspect this marker and explicitly run harness-unblock-root after changing the strategy, authority, or external blocking condition.\n'
		} > "$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$marker"
	fi
	rm -f "$(task_root_replan_file "$root")" "$(task_root_replanning_file "$root")"
	log_event "TASK_NEEDS_HUMAN root=$root trigger=$trigger_task reason=$(printf '%q' "$reason") marker=$marker"
	printf '%s\n' "$marker"
}

mark_root_needs_replan()
{
	local task_id="$1" reason="$2" trigger="$3"
	local blocker_class="${4:-}" remediation_scope="${5:-}" context_paths="${6:-}"
	local closure_condition="${7:-}" closure_repair_action="${8:-}" closure_repair_provider="${9:-}"
	local root marker progress blocking_fingerprint tmp
	root="$(task_root_id "$task_id")"
	marker="$(task_root_replan_file "$root")"
	if [[ -f "$marker" ]]; then
		printf '%s\n' "$marker"
		return 0
	fi
	progress="$(task_progress_file "$root")"
	blocking_fingerprint=""
	[[ ! -f "$progress" ]] ||
		blocking_fingerprint="$(awk -F': ' '$1 == "Blocking-Fingerprint" {print $2; exit}' "$progress")"
	[[ -n "$blocking_fingerprint" ]] || blocking_fingerprint="-"
	tmp="$marker.tmp.$$"
	{
		printf '# Root Task Needs Replanning\n\n'
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Task-Root: %s\n\n' "$root"
		printf 'Triggered-By: %s\n\n' "$task_id"
		printf 'Trigger-Outcome: %s\n\n' "$trigger"
		printf 'Paused-At: %s\n\n' "$(timestamp_utc)"
		printf 'Progress-Percent: %s%%\n\n' "$(task_progress_percent "$root")"
		printf 'Reason: %s\n\n' "$reason"
		if [[ -n "$blocker_class" ]]; then
			printf 'Blocker-Class: %s\n\n' "$blocker_class"
		fi
		if [[ -n "$remediation_scope" ]]; then
			printf 'Remediation-Scope: %s\n\n' "$remediation_scope"
		fi
		if [[ -n "$context_paths" ]]; then
			printf 'Context-Paths: %s\n\n' "$context_paths"
		fi
		if [[ -n "$closure_condition" ]]; then
			printf 'Closure-Condition: %s\n\n' "$closure_condition"
		fi
		if [[ -n "$closure_repair_action" ]]; then
			printf 'Closure-Repair-Action: %s\n\n' "$closure_repair_action"
		fi
		if [[ -n "$closure_repair_provider" ]]; then
			printf 'Closure-Repair-Provider: %s\n\n' "$closure_repair_provider"
		fi
		printf 'Reviewed-Attempts: %s\n' "$(root_reviewed_attempt_count "$root")"
		printf 'Reviewed-Attempts-Since-Last-Replan: %s\n' "$(root_reviewed_attempts_since_replan "$root")"
		printf 'Zero-Gain-Streak: %s\n' "$(root_zero_gain_streak "$root")"
		printf 'Checkpoints-Without-Criterion: %s\n\n' "$(root_checkpoint_without_criterion_streak "$root")"
		printf 'Blocking-Fingerprint: %s\n\n' "$blocking_fingerprint"
		if (( HARNESS_AUTO_REPLAN_ENABLED == 1 )); then
			printf 'All checkpoint artifacts, review records, progress history, and repository changes are preserved. The supervisor will resume the persistent manager to request one materially different continuation of the first unmet leaf with fresh worker context. Any new verified checkpoint resets escalation; human intervention is reserved for repeated strategies without durable gain or an explicit human-only boundary.\n'
		else
			printf 'All checkpoint artifacts, review records, progress history, and repository changes are preserved. Automatic replanning is disabled; reassess the active item, then run harness-unblock-root to grant a fresh convergence window.\n'
		fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$marker"
	log_event "TASK_NEEDS_REPLAN task=$task_id root=$root trigger=$trigger reason=$(printf '%q' "$reason") marker=$marker"
	printf '%s\n' "$marker"
}

maybe_mark_root_needs_replan()
{
	local task_id="$1" trigger="$2" root attempts zero_streak checkpoint_streak
	root="$(task_root_id "$task_id")"
	if task_root_needs_replan "$root"; then
		printf '%s\n' "$(task_root_replan_file "$root")"
		return 0
	fi
	attempts="$(root_reviewed_attempts_since_replan "$root")"
	if (( HARNESS_MAX_ROOT_ATTEMPTS > 0 && attempts >= HARNESS_MAX_ROOT_ATTEMPTS )); then
		mark_root_needs_replan "$task_id" \
			"reviewed root attempts reached the configured limit ($attempts/$HARNESS_MAX_ROOT_ATTEMPTS)" "$trigger"
		return 0
	fi
	zero_streak="$(root_zero_gain_streak "$root")"
	if (( HARNESS_MAX_ZERO_GAIN_WINDOW > 0 && zero_streak >= HARNESS_MAX_ZERO_GAIN_WINDOW )); then
		mark_root_needs_replan "$task_id" \
			"consecutive reviews without measured or checkpointed gain reached the configured limit ($zero_streak/$HARNESS_MAX_ZERO_GAIN_WINDOW)" "$trigger"
		return 0
	fi
	checkpoint_streak="$(root_checkpoint_without_criterion_streak "$root")"
	if (( HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION > 0 && checkpoint_streak >= HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION )); then
		mark_root_needs_replan "$task_id" \
			"verified increments without a completed root criterion reached the configured limit ($checkpoint_streak/$HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION)" "$trigger"
		return 0
	fi
	return 1
}

next_task_revision_id()
{
	local root dir path name revision max_revision=0
	root="$(task_root_id "$1")"
	dir="$(project_dir)"
	shopt -s nullglob
	for path in "$dir/tasks/$PROJECT-task-$root-revision-"* \
		"$dir/running/$PROJECT-task-$root-revision-"* \
		"$dir/results/$PROJECT-task-$root-revision-"* \
		"$dir/archive/$PROJECT-task-$root-revision-"* \
		"$dir/control/$PROJECT-task-$root-revision-"*; do
		[[ -e "$path" ]] || continue
		name="${path##*/}"
		if [[ "$name" =~ ^${PROJECT}-task-${root}-revision-([0-9]+)[.] ]]; then
			revision="${BASH_REMATCH[1]}"
			revision=$((10#$revision))
			(( revision <= max_revision )) || max_revision="$revision"
		fi
	done
	printf '%s-revision-%02d\n' "$root" "$((max_revision + 1))"
}

task_id_from_filename()
{
	local filename="$1"
	filename="${filename##*/}"
	filename="${filename#${PROJECT}-task-}"
	filename="${filename%.ready.md}"
	filename="${filename%.running.md}"
	filename="${filename%.result.md}"
	filename="${filename%.accepted.md}"
	filename="${filename%.checkpointed.md}"
	filename="${filename%.rejected.md}"
	filename="${filename%.blocked.md}"
	filename="${filename%.superseded.md}"
	printf '%s' "$filename"
}

config_value()
{
	local key="$1"
	local config
	config="$(project_dir)/project.conf"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$config"
}

session_file()
{
	local session="$1"
	printf '%s/control/sessions/%s.session' "$(project_dir)" "$session"
}

ensure_session()
{
	local session="$1"
	local file
	validate_session "$session"
	file="$(session_file "$session")"
	[[ -f "$file" ]] || die "unknown session: $session"
}

lease_value()
{
	local lease="$1"
	local key="$2"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$lease"
}

log_event()
{
	local dir
	dir="$(project_dir)"
	printf '%s\t%s\n' "$(timestamp_utc)" "$*" >> "$dir/logs/events.log"
}

trace_log_file()
{
	printf '%s/logs/trace.log' "$(project_dir)"
}

trace_init()
{
	local component="$1"
	local parent_trace_id="${HARNESS_TRACE_ID:-}"
	local nonce
	nonce="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s' "$$" "$(epoch_now)")"
	HARNESS_TRACE_PARENT_ID="$parent_trace_id"
	HARNESS_TRACE_COMPONENT="$component"
	HARNESS_TRACE_ID="${component}-$(date -u '+%Y%m%dT%H%M%SZ')-${nonce%%-*}"
	export HARNESS_TRACE_PARENT_ID HARNESS_TRACE_COMPONENT HARNESS_TRACE_ID
}

trace_event()
{
	local event="$1"
	shift || true
	local line
	line="$(timestamp_utc)"
	line+=" trace_id=$(printf '%q' "${HARNESS_TRACE_ID:-unknown}")"
	line+=" parent_trace_id=$(printf '%q' "${HARNESS_TRACE_PARENT_ID:-}")"
	line+=" component=$(printf '%q' "${HARNESS_TRACE_COMPONENT:-unknown}")"
	line+=" pid=$(printf '%q' "$$")"
	line+=" ppid=$(printf '%q' "$PPID")"
	line+=" event=$(printf '%q' "$event")"
	for field in "$@"; do
		line+=" $(printf '%q' "$field")"
	done
	printf '%s\n' "$line" >> "$(trace_log_file)"
}

trace_script_start()
{
	trace_event SCRIPT_START "argv_count=$#"
}

trace_script_exit()
{
	local status="$1"
	trace_event SCRIPT_EXIT "status=$status"
}

acquire_project_lock()
{
	local dir
	dir="$(project_dir)"
	exec 9>"$dir/control/project.lock"
	flock -x 9
}

kv_file_value()
{
	local file="$1"
	local key="$2"
	[[ -f "$file" ]] || die "key-value file does not exist: $file"
	awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

env_sha256()
{
	sha256sum "$HARNESS_ENV_FILE" | awk '{print $1}'
}

env_path_sha256()
{
	printf '%s' "$HARNESS_ENV_FILE" | sha256sum | awk '{print $1}'
}

env_command_lock_path()
{
	local dir
	dir="$HARNESS_ROOT/control/env-locks"
	mkdir -p "$dir"
	chmod 700 "$HARNESS_ROOT" "$HARNESS_ROOT/control" "$dir" 2>/dev/null || true
	printf '%s/%s.lock' "$dir" "$(env_path_sha256)"
}

acquire_env_command_lock()
{
	local operation="$1"
	local lock_file lock_pid
	lock_file="$(env_command_lock_path)"
	while true; do
		if ( set -o noclobber; printf 'pid=%s\nstarted_at=%s\noperation=%s\nenv_file=%s\n' \
			"${BASHPID:-$$}" "$(timestamp_utc)" "$operation" "$HARNESS_ENV_FILE" > "$lock_file" ) 2>/dev/null; then
			chmod 600 "$lock_file"
			export HARNESS_ENV_COMMAND_LOCK_FILE="$lock_file"
			trap 'release_env_command_lock' EXIT
			return 0
		fi

		lock_pid="$(kv_file_value "$lock_file" pid 2>/dev/null || true)"
		if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
			die "$operation is already running for ENV_FILE $HARNESS_ENV_FILE"
		fi
		rm -f "$lock_file"
	done
}

release_env_command_lock()
{
	local lock_file lock_pid
	lock_file="${HARNESS_ENV_COMMAND_LOCK_FILE:-}"
	[[ -n "$lock_file" && -f "$lock_file" ]] || return 0
	lock_pid="$(kv_file_value "$lock_file" pid 2>/dev/null || true)"
	if [[ "$lock_pid" == "${BASHPID:-$$}" ]]; then
		rm -f "$lock_file"
	fi
}

env_process_lines()
{
	local pid ppid proc arg has_harness_path has_env_file harness_command
	local -a argv
	local -A ignore_pid
	pid="${BASHPID:-$$}"
	while [[ -n "$pid" && "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
		ignore_pid["$pid"]=1
		ppid="$(ps -o ppid= -p "$pid" | tr -d '[:space:]')"
		[[ -n "$ppid" && "$ppid" != "$pid" ]] || break
		pid="$ppid"
	done

	# Inspect argv boundaries from procfs. Searching flattened `ps` output makes
	# an orchestration shell look like every harness named inside its command
	# text, which can falsely reject otherwise independent detached starts.
	for proc in /proc/[0-9]*; do
		pid="${proc##*/}"
		[[ -z "${ignore_pid[$pid]:-}" && -r "$proc/cmdline" ]] || continue
		argv=()
		while IFS= read -r -d '' arg; do
			argv+=("$arg")
		done < "$proc/cmdline" || true
		(( ${#argv[@]} > 0 )) || continue
		case "${argv[0]##*/}" in
			bash|sh) ;;
			*) continue ;;
		esac
		has_harness_path=0
		has_env_file=0
		harness_command=""
		for arg in "${argv[@]}"; do
			if [[ "$arg" == "$HARNESS_BIN/"* ]]; then
				has_harness_path=1
				[[ -n "$harness_command" ]] || harness_command="${arg##*/}"
			fi
			[[ "$arg" == "$HARNESS_ENV_FILE" ]] && has_env_file=1
		done
		if (( has_harness_path == 1 && has_env_file == 1 )); then
			# Reporting/watch commands are concurrent observers, not owners of an
			# environment. Treating their short-lived helper processes as active
			# agents makes harness-start fail nondeterministically during refresh.
			case "$harness_command" in
				harness-status|harness-agent-token-usage|harness-agent-cost-usage|harness-costs|\
				harness-statistics|harness-info|harness-watch-*|harness-implementation-log|\
				harness-decomposition-tree|harness-decomposition-metrics|harness-complexity|harness-architecture-status|\
				harness-metrics|harness-token-outliers|harness-project-path|harness-repository-path|\
				harness-state-path|harness-show-*|harness-check-env)
					continue
					;;
			esac
			ps -o pid=,comm=,args= -p "$pid"
		fi
	done
}

env_has_running_processes()
{
	[[ -n "$(env_process_lines)" ]]
}

project_supervisors_running()
{
	local dir pid_file pid
	dir="$(project_dir)"
	for pid_file in "$dir/control/supervisor.pid" "$dir/control/worker-supervisor.pid"; do
		[[ -f "$pid_file" ]] || continue
		pid="$(<"$pid_file")"
		if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	done
	return 1
}

confirm_reset_state()
{
	local reason="$1"
	local reply
	printf '%s\n' "$reason" >&2
	printf 'Reset current state for %s? [y/N] ' "$HARNESS_ENV_FILE" >&2
	if ! IFS= read -r reply; then
		die 'reset confirmation was not provided'
	fi
	[[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

reset_project_state()
{
	local dir backup_root backup_dir
	dir="$(project_dir)"

	if [[ -d "$dir" ]]; then
		if [[ -f "$dir/control/worker-supervisor.pid" || -f "$dir/control/supervisor.pid" ]]; then
			"$HARNESS_BIN/worker-supervisor-stop" "$HARNESS_ENV_FILE" >/dev/null 2>&1 || true
			"$HARNESS_BIN/manager-supervisor-stop" "$HARNESS_ENV_FILE" >/dev/null 2>&1 || true
		fi
		sleep 0.2
	fi

	if env_has_running_processes; then
		printf 'Active processes still reference %s:\n' "$HARNESS_ENV_FILE" >&2
		env_process_lines >&2
		die 'refusing to reset while environment-bound processes are still running'
	fi

	[[ -d "$dir" ]] || return 0

	backup_root="$HARNESS_ROOT/resets"
	backup_dir="$backup_root/${PROJECT}-$(timestamp_compact_utc)-$$"
	mkdir -p "$backup_root"
	chmod 700 "$backup_root"
	mv "$dir" "$backup_dir"
	printf 'Previous state moved to %s\n' "$backup_dir" >&2
}

initialize_project_state()
{
	umask 077
	mkdir -p "$HARNESS_ROOT"
	chmod 700 "$HARNESS_ROOT"
	mkdir -p "$(project_tmp_dir)"
	chmod 700 "$(project_tmp_dir)"
	mkdir -p "$(project_dir)"/{tasks,running,results,archive/goal-iterations,archive/goals,control/sessions,control/progress,control/goals,logs}
	chmod 700 "$(project_dir)" "$(project_dir)"/{tasks,running,results,archive,archive/goal-iterations,archive/goals,control,control/sessions,control/progress,control/goals,logs}

	write_project_snapshot
	write_manager_snapshot
	write_worker_snapshot
	write_oracle_snapshot
}

project_complete_file()
{
	printf '%s/control/project.complete' "$(project_dir)"
}

project_oracle_dir()
{
	printf '%s/control/oracle' "$(project_dir)"
}

project_oracle_pending_file()
{
	printf '%s/oracle.pending.md' "$(project_oracle_dir)"
}

project_block_file()
{
	printf '%s/control/project.blocked.md' "$(project_dir)"
}

specification_review_state_file()
{
	printf '%s/control/specification-review.env' "$(project_dir)"
}

architecture_redesign_state_file()
{
	printf '%s/control/architecture-redesign-review.env' "$(project_dir)"
}

architecture_fit_state_file()
{
	printf '%s/control/architecture-fit-review.env' "$(project_dir)"
}

decomposition_candidate_state_file()
{
	printf '%s/control/decomposition-candidate.env' "$(project_dir)"
}

decomposition_dag_candidate_state_file()
{
	printf '%s/control/decomposition-dag-candidate.env' "$(project_dir)"
}

architecture_redesign_force_file()
{
	printf '%s/control/architecture-redesign-force.env' "$(project_dir)"
}

domain_profile_names()
{
	local value name
	value="${HARNESS_DOMAIN_PROFILES:-}"
	[[ -n "$value" ]] || return 0
	value="${value//,/ }"
	for name in $value; do
		[[ -n "$name" ]] && printf '%s\n' "$name"
	done
}

domain_profile_file()
{
	local name="$1" repository_profile harness_profile
	[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid domain profile name: $name"
	repository_profile="$REPOSITORY/.harness/domain-profiles/$name.tsv"
	harness_profile="$HARNESS_HOME/domain-theory/$name.tsv"
	if [[ -f "$repository_profile" ]]; then
		printf '%s\n' "$repository_profile"
	elif [[ -f "$harness_profile" ]]; then
		printf '%s\n' "$harness_profile"
	else
		die "domain profile does not exist: $name (checked $repository_profile and $harness_profile)"
	fi
}

validate_domain_profile_file()
{
	local name="$1" file="$2" header invariant_id category statement source_authority validation_hint extra count=0
	local -A seen=()
	IFS= read -r header < "$file" || die "domain profile is empty: $name"
	[[ "$header" == $'invariant_id\tcategory\tstatement\tsource_authority\tvalidation_hint' ]] ||
		die "domain profile $name has an unsupported header"
	while IFS=$'\t' read -r invariant_id category statement source_authority validation_hint extra; do
		[[ -n "${invariant_id:-}${category:-}${statement:-}${source_authority:-}${validation_hint:-}${extra:-}" ]] || continue
		[[ -n "$invariant_id" && -n "$category" && -n "$statement" && -n "$source_authority" && -n "$validation_hint" && -z "${extra:-}" ]] ||
			die "domain profile $name rows require exactly five nonempty fields"
		[[ "$invariant_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid invariant ID in domain profile $name: $invariant_id"
		[[ -z "${seen[$invariant_id]:-}" ]] || die "duplicate invariant ID in domain profile $name: $invariant_id"
		seen[$invariant_id]=1
		[[ "$category" =~ ^(CONTRACT|DETERMINISM|OWNERSHIP|SERIALIZATION|ERROR|CONCURRENCY|COMPATIBILITY|TESTING|SECURITY|PERFORMANCE|RESOURCE_LIFETIME)$ ]] ||
			die "invalid invariant category in domain profile $name: $category"
		[[ "$source_authority" =~ ^(STANDARD|PROJECT_POLICY|EXPLICIT_PROFILE)$ ]] ||
			die "invalid source authority in domain profile $name: $source_authority"
		count=$((count + 1))
	done < <(tail -n +2 "$file")
	(( count > 0 )) || die "domain profile has no invariants: $name"
}

validate_domain_profiles_configuration()
{
	local name file
	local -A seen=()
	while IFS= read -r name; do
		[[ -z "${seen[$name]:-}" ]] || die "duplicate HARNESS_DOMAIN_PROFILES entry: $name"
		seen[$name]=1
		file="$(domain_profile_file "$name")"
		validate_domain_profile_file "$name" "$file"
	done < <(domain_profile_names)
}

domain_profiles_sha256()
{
	local name file found=0
	{
		while IFS= read -r name; do
			found=1
			file="$(domain_profile_file "$name")"
			printf '%s\t%s\n' "$name" "$(sha256sum "$file" | awk '{print $1}')"
		done < <(domain_profile_names)
		(( found == 1 )) || printf 'none\n'
	} | sha256sum | awk '{print $1}'
}

specification_review_repository_dir()
{
	printf '%s/spec-review' "$REPOSITORY"
}

architecture_redesign_repository_dir()
{
	printf '%s/architecture-review' "$REPOSITORY"
}

specification_sha256()
{
	[[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]] || { printf 'missing\n'; return 0; }
	sha256sum "$SPECIFICATION" | awk '{print $1}'
}

# Return success when a cited repository source contains WANTED in the first
# complete fenced region at or shortly after one of LOCATIONS. Specification
# reviewers and independent critics must share this check so a challenge cannot
# bypass deterministic validation applied to the initial review.
specification_fenced_source_region_contains_id()
{
	local locations="$1" wanted="$2" location source_path source_line
	while IFS= read -r location; do
		location="${location#${location%%[![:space:]]*}}"
		location="${location%${location##*[![:space:]]}}"
		[[ "$location" =~ ^([^,]+):([0-9]+)$ ]] || continue
		source_path="${BASH_REMATCH[1]}"
		source_line="${BASH_REMATCH[2]}"
		[[ "$source_path" != /* && "$source_path" != .. && "$source_path" != ../* && "$source_path" != */../* ]] || continue
		[[ -f "$REPOSITORY/$source_path" ]] || continue
		awk -v start="$source_line" -v wanted="$wanted" '
			NR < start {next}
			!inside && NR > start + 100 {exit}
			!inside && /^```/ {inside=1; next}
			inside && /^```/ {exit}
			inside && index($0, wanted) {found=1}
			END {exit found ? 0 : 1}
		' "$REPOSITORY/$source_path" && return 0
	done < <(printf '%s\n' "$locations" | tr ',' '\n')
	return 1
}

validate_specification_issue_source_claims()
{
	local issue_id="$1" source_locations="$2" combined_claim_text="$3" omitted_id
	while IFS= read -r omitted_id; do
		[[ -n "$omitted_id" ]] || continue
		if specification_fenced_source_region_contains_id "$source_locations" "$omitted_id"; then
			die "specification issue $issue_id is contradicted by its cited source: allegedly omitted $omitted_id is present in the complete fenced registry"
		fi
	done < <(printf '%s\n' "$combined_claim_text" |
		grep -Eio 'omit(s|ted|ting)?[[:space:]]+`?[A-Za-z][A-Za-z0-9._:-]*`?' |
		sed -E 's/^omit(s|ted|ting)?[[:space:]]+`?//I; s/`$//' || true)
}

# Emit explicit requirement prerequisites found in the two structured forms
# used by harness specifications: Markdown requirement tables and the optional
# inline machine-readable registry. The output has no header:
# subject<TAB>dependency<TAB>source:line.
specification_explicit_dependencies()
{
	[[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]] || return 0
	awk '
		function trim(value) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			gsub(/^[`]+|[`]+$/, "", value)
			return value
		}
		function valid_id(value) {
			return value ~ /^[A-Za-z0-9][A-Za-z0-9._:-]*$/ && value != "-" && value != "none" && value != "NONE"
		}
		function emit_dependencies(subject, value, location, count, parts, dependency) {
			sub(/^[[:space:]]*\[/, "", value)
			sub(/\][[:space:]]*$/, "", value)
			gsub(/[`]/, "", value)
			count=split(value, parts, /[[:space:],]+/)
			for (i=1; i<=count; i++) {
				dependency=trim(parts[i])
				if (valid_id(subject) && valid_id(dependency))
					print subject "\t" dependency "\t" location
			}
		}
		/^[#]+[[:space:]]+/ {
			heading=$0
			sub(/^[#]+[[:space:]]+/, "", heading)
			split(heading, heading_parts, /[[:space:]]+/)
			candidate=trim(heading_parts[1])
			if (valid_id(candidate)) current=candidate
		}
		/^\|[[:space:]]*(Requirement ID|Goal ID|Test ID)[[:space:]]*\|/ {
			split($0, cells, "|")
			candidate=trim(cells[3])
			if (valid_id(candidate)) current=candidate
		}
		/^\|[[:space:]]*Dependencies[[:space:]]*\|/ {
			split($0, cells, "|")
			emit_dependencies(current, trim(cells[3]), FILENAME ":" FNR)
		}
		/^[[:space:]]*-[[:space:]]*\{id:[[:space:]]*/ {
			entry=$0
			id_text=entry
			sub(/^[[:space:]]*-[[:space:]]*\{id:[[:space:]]*/, "", id_text)
			split(id_text, id_parts, ",")
			registry_id=trim(id_parts[1])
			if (match(entry, /dependencies:[[:space:]]*\[[^]]*\]/)) {
				dependency_text=substr(entry, RSTART, RLENGTH)
				sub(/^dependencies:[[:space:]]*/, "", dependency_text)
				emit_dependencies(registry_id, dependency_text, FILENAME ":" FNR)
			}
		}
	' "$SPECIFICATION" | sort -u
}

specification_explicit_dependency_cycle()
{
	local dependencies_file
	dependencies_file="${1:-}"
	if [[ -n "$dependencies_file" ]]; then
		[[ -s "$dependencies_file" ]] || return 1
		! awk -F '\t' '{print $1, $2}' "$dependencies_file" | tsort >/dev/null 2>&1
	else
		! specification_explicit_dependencies | awk -F '\t' '{print $1, $2}' | tsort >/dev/null 2>&1
	fi
}

# Return only source edges that participate in a strongly connected component.
# This keeps deterministic clarification reports focused when a large registry
# contains one small cycle.
specification_explicit_dependency_cycle_edges()
{
	specification_explicit_dependencies | awk -F '\t' '
		{
			key=$1 SUBSEP $2
			if (!(key in edge_location)) edge_location[key]=$3
			nodes[$1]=1; nodes[$2]=1; reach[$1 SUBSEP $2]=1
		}
		END {
			do {
				changed=0
				for (middle in nodes)
					for (left in nodes)
						if ((left SUBSEP middle) in reach)
							for (right in nodes)
								if (((middle SUBSEP right) in reach) && !((left SUBSEP right) in reach)) {
									reach[left SUBSEP right]=1
									changed=1
								}
			} while (changed)
			for (key in edge_location) {
				split(key, parts, SUBSEP)
				if ((parts[2] SUBSEP parts[1]) in reach)
					print parts[1] "\t" parts[2] "\t" edge_location[key]
			}
		}
	' | sort
}

specification_renormalization_stall_file()
{
	printf '%s/control/specification-renormalization-stalled.env' "$(project_dir)"
}

specification_renormalization_stall_matches_current_inputs()
{
	local stall
	stall="$(specification_renormalization_stall_file)"
	[[ -f "$stall" ]] || return 1
	[[ "$(kv_file_value "$stall" specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(kv_file_value "$stall" repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(kv_file_value "$stall" domain_profiles_sha256)" == "$(domain_profiles_sha256)" ]]
}

specification_review_repository_baseline()
{
	git -C "$REPOSITORY" rev-parse HEAD 2>/dev/null || printf 'unversioned\n'
}

specification_review_state_value()
{
	local key="$1" fallback="${2:-}" state value=""
	state="$(specification_review_state_file)"
	if [[ -f "$state" ]]; then
		value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$state")"
	fi
	[[ -n "$value" ]] || value="$fallback"
	printf '%s' "$value"
}

specification_review_matches_current_inputs()
{
	local state
	state="$(specification_review_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(specification_review_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(specification_review_state_value repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(specification_review_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]]
}

specification_review_authority_matches()
{
	local state
	state="$(specification_review_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(specification_review_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(specification_review_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]]
}

specification_review_baseline_is_valid()
{
	local accepted_baseline current_baseline
	accepted_baseline="$(specification_review_state_value repository_baseline)"
	current_baseline="$(specification_review_repository_baseline)"
	[[ -n "$accepted_baseline" ]] || return 1
	[[ "$accepted_baseline" == "$current_baseline" ]] && return 0
	# Before DAG registration the review is a transaction over one exact source
	# baseline. Afterwards normal task commits advance HEAD; the accepted baseline
	# remains valid only while it is still an ancestor of the implementation.
	project_plan_exists || return 1
	[[ "$accepted_baseline" != unversioned && "$current_baseline" != unversioned ]] || return 1
	git -C "$REPOSITORY" merge-base --is-ancestor "$accepted_baseline" "$current_baseline" >/dev/null 2>&1
}

specification_review_is_accepted()
{
	(( HARNESS_SPECIFICATION_REVIEW_ENABLED == 0 )) && return 0
	specification_review_authority_matches || return 1
	[[ "$(specification_review_state_value status)" == ACCEPTED ]] || return 1
	specification_review_baseline_is_valid
}

specification_review_requires_clarification()
{
	(( HARNESS_SPECIFICATION_REVIEW_ENABLED == 1 )) || return 1
	specification_review_matches_current_inputs || return 1
	[[ "$(specification_review_state_value status)" == SPEC_CLARIFICATION_REQUIRED ]]
}

specification_review_report_relative_path()
{
	specification_review_state_value report
}

architecture_redesign_state_value()
{
	local key="$1" fallback="${2:-}" state value=""
	state="$(architecture_redesign_state_file)"
	if [[ -f "$state" ]]; then
		value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$state")"
	fi
	[[ -n "$value" ]] || value="$fallback"
	printf '%s' "$value"
}

architecture_fit_state_value()
{
	local key="$1" fallback="${2:-}" state value=""
	state="$(architecture_fit_state_file)"
	if [[ -f "$state" ]]; then
		value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$state")"
	fi
	[[ -n "$value" ]] || value="$fallback"
	printf '%s' "$value"
}

architecture_fit_matches_current_inputs()
{
	local state
	state="$(architecture_fit_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(architecture_fit_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(architecture_fit_state_value repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(architecture_fit_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]]
}

architecture_fit_is_accepted()
{
	project_plan_exists && return 0
	architecture_redesign_force_matches_current_inputs && return 0
	architecture_fit_matches_current_inputs || return 1
	[[ "$(architecture_fit_state_value status)" == ACCEPTED ]]
}

decomposition_candidate_state_value()
{
	local key="$1" fallback="${2:-}" state value=""
	state="$(decomposition_candidate_state_file)"
	if [[ -f "$state" ]]; then
		value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$state")"
	fi
	[[ -n "$value" ]] || value="$fallback"
	printf '%s' "$value"
}

decomposition_candidate_matches_current_inputs()
{
	local state
	state="$(decomposition_candidate_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(decomposition_candidate_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(decomposition_candidate_state_value repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(decomposition_candidate_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]] || return 1
	[[ -z "$(decomposition_candidate_state_value complexity_contract_sha256)" ||
		"$(decomposition_candidate_state_value complexity_contract_sha256)" == "$(complexity_contract_sha256)" ]]
}

decomposition_repair_diagnostic_fingerprint()
{
	local diagnostic="$1"
	[[ -f "$diagnostic" ]] || return 1
	{ grep -E '^(ERROR:|LUNA_COMPLEXITY_|CONTEXT_CLOSURE_)' "$diagnostic" || true; } |
		sed -E \
			-e 's#\.tmp\.[0-9]+#.tmp.PID#g' \
			-e 's#/decomposition-candidates/[0-9a-f]{64}/#/decomposition-candidates/CANDIDATE/#g' \
			-e 's#(terra_exception=)[^;]*(;|$)#\1<VALUE>\2#g' |
		sha256sum | awk '{print $1}'
}

decomposition_dag_candidate_state_value()
{
	local key="$1" fallback="${2:-}" state value=""
	state="$(decomposition_dag_candidate_state_file)"
	if [[ -f "$state" ]]; then
		value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$state")"
	fi
	[[ -n "$value" ]] || value="$fallback"
	printf '%s' "$value"
}

decomposition_dag_candidate_matches_current_inputs()
{
	local state
	state="$(decomposition_dag_candidate_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(decomposition_dag_candidate_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(decomposition_dag_candidate_state_value repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(decomposition_dag_candidate_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]] || return 1
	[[ -z "$(decomposition_dag_candidate_state_value complexity_contract_sha256)" ||
		"$(decomposition_dag_candidate_state_value complexity_contract_sha256)" == "$(complexity_contract_sha256)" ]]
}

architecture_redesign_matches_current_inputs()
{
	local state
	state="$(architecture_redesign_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(architecture_redesign_state_value specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(architecture_redesign_state_value repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(architecture_redesign_state_value domain_profiles_sha256 none)" == "$(domain_profiles_sha256)" ]]
}

architecture_redesign_force_matches_current_inputs()
{
	local force report_relative report report_sha
	force="$(architecture_redesign_force_file)"
	[[ -f "$force" ]] || return 1
	architecture_redesign_matches_current_inputs || return 1
	[[ "$(kv_file_value "$force" specification_sha256)" == "$(specification_sha256)" ]] || return 1
	[[ "$(kv_file_value "$force" repository_baseline)" == "$(specification_review_repository_baseline)" ]] || return 1
	[[ "$(kv_file_value "$force" domain_profiles_sha256)" == "$(domain_profiles_sha256)" ]] || return 1
	report_relative="$(architecture_redesign_state_value report)"
	[[ -n "$report_relative" && "$report_relative" != /* ]] || return 1
	report="$(realpath -m "$REPOSITORY/$report_relative")"
	case "$report" in "$REPOSITORY"/*) ;; *) return 1 ;; esac
	[[ -f "$report" ]] || return 1
	report_sha="$(sha256sum "$report" | awk '{print $1}')"
	[[ "$(kv_file_value "$force" report_sha256)" == "$report_sha" ]]
}

architecture_redesign_requires_action()
{
	project_plan_exists && return 1
	architecture_redesign_matches_current_inputs || return 1
	[[ "$(architecture_redesign_state_value status)" == ARCHITECTURE_REDESIGN_REQUIRED ]] || return 1
	! architecture_redesign_force_matches_current_inputs
}

architecture_redesign_report_relative_path()
{
	architecture_redesign_state_value report
}

architecture_redesign_record_force_waiver()
{
	local force report_relative report report_sha tmp waiver_id
	(( HARNESS_ARCHITECTURE_GUARDS == 1 )) || die '--force-decomposition requires HARNESS_ARCHITECTURE_GUARDS=1 so remediation dependencies and critical debt remain machine-enforced'
	architecture_redesign_matches_current_inputs || die 'no current architecture redesign review matches the specification and repository baseline'
	[[ "$(architecture_redesign_state_value status)" == ARCHITECTURE_REDESIGN_REQUIRED ]] ||
		die 'the current architecture review does not require redesign'
	architecture_redesign_force_matches_current_inputs && return 0
	force="$(architecture_redesign_force_file)"
	report_relative="$(architecture_redesign_state_value report)"
	report="$(realpath -m "$REPOSITORY/$report_relative")"
	[[ -f "$report" ]] || die "architecture redesign report is missing: $report"
	report_sha="$(sha256sum "$report" | awk '{print $1}')"
	waiver_id="$(printf '%s\n' "$PROJECT" "$(specification_sha256)" "$(specification_review_repository_baseline)" "$report_sha" "$(timestamp_utc)" "$UID" | sha256sum | awk '{print $1}')"
	tmp="$force.tmp.$$"
	{
		printf 'status=FORCE_DECOMPOSITION_AUTHORIZED\n'
		printf 'waiver_id=%s\n' "$waiver_id"
		printf 'specification_sha256=%s\n' "$(specification_sha256)"
		printf 'repository_baseline=%s\n' "$(specification_review_repository_baseline)"
		printf 'domain_profiles_sha256=%s\n' "$(domain_profiles_sha256)"
		printf 'report=%s\n' "$report_relative"
		printf 'report_sha256=%s\n' "$report_sha"
		printf 'operator_uid=%s\n' "$UID"
		printf 'operator_name=%s\n' "$(id -un 2>/dev/null || printf unknown)"
		printf 'authorized_at=%s\n' "$(timestamp_utc)"
		printf 'authority=COMMAND_LINE_FORCE_DECOMPOSITION\n'
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$force"
	log_event "ARCHITECTURE_REDESIGN_FORCE_AUTHORIZED waiver_id=$waiver_id report=$report_relative report_sha256=$report_sha operator_uid=$UID"
}

specification_obligations_file()
{
	local relative
	relative="$(specification_review_state_value obligations)"
	[[ -n "$relative" ]] || return 1
	printf '%s/%s\n' "$REPOSITORY" "$relative"
}

specification_relations_file()
{
	local relative
	relative="$(specification_review_state_value relations)"
	[[ -n "$relative" ]] || return 1
	printf '%s/%s\n' "$REPOSITORY" "$relative"
}

specification_repository_inventory_file()
{
	local relative
	relative="$(specification_review_state_value inventory)"
	[[ -n "$relative" ]] || return 1
	printf '%s/%s\n' "$REPOSITORY" "$relative"
}

specification_domain_manifest_file()
{
	local relative
	relative="$(specification_review_state_value domain_manifest)"
	[[ -n "$relative" ]] || return 1
	printf '%s/%s\n' "$REPOSITORY" "$relative"
}

specification_coverage_file()
{
	printf '%s/control/specification-coverage.tsv' "$(project_dir)"
}

specification_ir_available()
{
	specification_review_is_accepted || return 1
	[[ -f "$(specification_obligations_file 2>/dev/null)" && -f "$(specification_relations_file 2>/dev/null)" ]]
}

specification_ir_registered()
{
	local state
	state="$(specification_review_state_file)"
	[[ -f "$state" ]] || return 1
	[[ "$(specification_review_state_value status)" == ACCEPTED ]] || return 1
	[[ -n "$(specification_review_state_value obligations)" && -n "$(specification_review_state_value relations)" ]]
}

require_registered_specification_ir()
{
	specification_ir_registered || return 0
	specification_ir_available ||
		die 'registered Specification IR is no longer authoritative for the current specification, domain profiles, or repository history'
	if project_plan_exists; then
		[[ -f "$(specification_coverage_file)" ]] || die 'registered Specification IR project is missing obligation-to-DAG coverage'
	fi
}

validate_specification_coverage_relations()
{
	local coverage="$1" dag="$2" relations
	relations="$(specification_relations_file)"
	awk -F '\t' -v coverage_file="$coverage" -v dag_file="$dag" -v relations_file="$relations" '
		function trim(value) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); return value}
		function node_follows_obligation(node, object, key, parts) {
			for (key in covers) {
				split(key, parts, SUBSEP)
				if (parts[1] == object && (parts[2] == node || ((node SUBSEP parts[2]) in reach))) return 1
			}
			return 0
		}
		function all_subject_nodes_follow(subject, object, key, parts, found) {
			found=0
			for (key in covers) {
				split(key, parts, SUBSEP)
				if (parts[1] != subject) continue
				found=1
				if (!node_follows_obligation(parts[2], object)) return 0
			}
			return found
		}
		function some_subject_node_follows(subject, object, key, parts) {
			for (key in covers) {
				split(key, parts, SUBSEP)
				if (parts[1] == subject && node_follows_obligation(parts[2], object)) return 1
			}
			return 0
		}
		function node_follows_any_producer(node, artifact, key, parts) {
			for (key in producers) {
				split(key, parts, SUBSEP)
				if (parts[1] == artifact && node_follows_obligation(node, parts[2])) return 1
			}
			return 0
		}
		function artifact_has_producer(artifact, key, parts) {
			for (key in producers) {split(key, parts, SUBSEP); if (parts[1] == artifact) return 1}
			return 0
		}
		FILENAME == coverage_file {
			if (FNR == 1) next
			n=split($2, values, ",")
			for (i=1; i<=n; i++) covers[$1 SUBSEP trim(values[i])]=1
			next
		}
		FILENAME == dag_file {
			if (FNR == 1) next
			node=$1
			n=split($3, values, ",")
			for (i=1; i<=n; i++) {
				dependency=trim(values[i])
				if (dependency == "-") continue
				reach[node SUBSEP dependency]=1
				# The decomposition validator guarantees topological order, so
				# every dependency already has its complete ancestor set.
				for (key in reach) {
					split(key, parts, SUBSEP)
					if (parts[1] == dependency)
						reach[node SUBSEP parts[2]]=1
				}
			}
			next
		}
		FILENAME == relations_file {
			if (FNR == 1) next
			count++
			type[count]=$2; subject[count]=$3; object[count]=$4; relation_id[count]=$1; authority[count]=$5
			if ($2 == "PRODUCES" && $5 != "PLANNING_HINT") producers[$4 SUBSEP $3]=1
			next
		}
		END {
			for (i=1; i<=count; i++) {
				if (authority[i] == "PLANNING_HINT") continue
				if (type[i] == "DEPENDS_ON" || type[i] == "REQUIRES_ACCEPTED") {
					if (!all_subject_nodes_follow(subject[i], object[i])) {
						printf "coverage violates %s relation %s: %s must follow %s\n", type[i], relation_id[i], subject[i], object[i] > "/dev/stderr"
						errors++
					}
				} else if (type[i] == "INTEGRATION_DEPENDENCY_ONLY" || type[i] == "REGRESSION_BOUNDARY" || type[i] == "FINAL_HEALTH_DEPENDENCY") {
					if (!some_subject_node_follows(subject[i], object[i])) {
						printf "coverage lacks a downstream node for %s relation %s: %s -> %s\n", type[i], relation_id[i], subject[i], object[i] > "/dev/stderr"
						errors++
					}
				} else if (type[i] == "CONSUMES" && artifact_has_producer(object[i])) {
					for (key in covers) {
						split(key, cparts, SUBSEP)
						if (cparts[1] == subject[i] && !node_follows_any_producer(cparts[2], object[i])) {
							printf "consumer node %s does not follow a producer of %s (%s)\n", cparts[2], object[i], relation_id[i] > "/dev/stderr"
							errors++
						}
					}
				}
			}
			exit(errors ? 1 : 0)
		}
	' "$coverage" "$dag" "$relations" || die 'specification coverage conflicts with typed semantic relations'
}

validate_specification_coverage_file()
{
	local coverage="$1" dag="$2" header obligation_id node_ids evidence_plan extra node_id
	local obligations_file
	local -A obligations=() dag_nodes=() covered_obligations=() covered_nodes=()
	[[ -f "$coverage" ]] || die "specification coverage file does not exist: $coverage"
	[[ -f "$dag" ]] || die "decomposition DAG does not exist for specification coverage: $dag"
	obligations_file="$(specification_obligations_file)"
	while IFS=$'\t' read -r obligation_id _; do
		[[ "$obligation_id" != obligation_id && -n "$obligation_id" ]] && obligations[$obligation_id]=1
	done < "$obligations_file"
	while IFS=$'\t' read -r node_id _; do
		[[ "$node_id" != node_id && -n "$node_id" ]] && dag_nodes[$node_id]=1
	done < "$dag"
	IFS= read -r header < "$coverage" || die 'specification coverage file is empty'
	[[ "$header" == $'obligation_id\tnode_ids\tevidence_plan' ]] ||
		die 'specification coverage header must be: obligation_id<TAB>node_ids<TAB>evidence_plan'
	while IFS=$'\t' read -r obligation_id node_ids evidence_plan extra; do
		[[ -n "${obligation_id:-}${node_ids:-}${evidence_plan:-}${extra:-}" ]] || continue
		[[ -n "$obligation_id" && -n "$node_ids" && "$node_ids" != - && -n "$evidence_plan" && -z "${extra:-}" ]] ||
			die "invalid specification coverage row: ${obligation_id:-empty}"
		[[ -n "${obligations[$obligation_id]:-}" ]] || die "coverage references unknown obligation: $obligation_id"
		[[ -z "${covered_obligations[$obligation_id]:-}" ]] || die "duplicate specification coverage row: $obligation_id"
		covered_obligations[$obligation_id]=1
		IFS=',' read -r -a coverage_nodes <<< "$node_ids"
		for node_id in "${coverage_nodes[@]}"; do
			node_id="$(trim_surrounding_whitespace "$node_id")"
			[[ -n "${dag_nodes[$node_id]:-}" ]] || die "coverage for $obligation_id references unknown DAG node: $node_id"
			covered_nodes[$node_id]=1
		done
	done < <(tail -n +2 "$coverage")
	for obligation_id in "${!obligations[@]}"; do
		[[ -n "${covered_obligations[$obligation_id]:-}" ]] || die "normalized specification obligation is absent from DAG coverage: $obligation_id"
	done
	for node_id in "${!dag_nodes[@]}"; do
		[[ -n "${covered_nodes[$node_id]:-}" ]] || die "DAG node is not justified by a normalized specification obligation: $node_id"
	done
	validate_specification_coverage_relations "$coverage" "$dag"
}

specification_obligation_count()
{
	local file
	file="$(specification_obligations_file 2>/dev/null || true)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk 'NR > 1 {n++} END {print n+0}' "$file"
}

specification_coverage_mapped_count()
{
	local file
	file="$(specification_coverage_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk 'NR > 1 {n++} END {print n+0}' "$file"
}

specification_coverage_verified_count()
{
	local coverage obligation_id node_ids evidence_plan node_id verified count=0
	coverage="$(specification_coverage_file)"
	[[ -f "$coverage" && -f "$(project_plan_state_file)" ]] || { printf '0\n'; return 0; }
	while IFS=$'\t' read -r obligation_id node_ids evidence_plan; do
		[[ "$obligation_id" != obligation_id && -n "$obligation_id" ]] || continue
		verified=1
		IFS=',' read -r -a coverage_nodes <<< "$node_ids"
		for node_id in "${coverage_nodes[@]}"; do
			node_id="$(trim_surrounding_whitespace "$node_id")"
			[[ "$(project_plan_item_status "$node_id")" == COMPLETE ]] || { verified=0; break; }
		done
		(( verified == 0 )) || count=$((count + 1))
	done < <(tail -n +2 "$coverage")
	printf '%s\n' "$count"
}

specification_obligations_for_node()
{
	local wanted="$1" coverage
	coverage="$(specification_coverage_file)"
	[[ -f "$coverage" ]] || return 0
	awk -F '\t' -v wanted="$wanted" '
		NR > 1 {
			n=split($2, nodes, ",")
			for (i=1; i<=n; i++) {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", nodes[i])
				if (nodes[i] == wanted) {print $1; break}
			}
		}
	' "$coverage"
}

specification_coverage_completion_ready()
{
	specification_ir_registered || return 0
	specification_ir_available || return 1
	[[ -f "$(specification_coverage_file)" ]] || return 1
	validate_specification_coverage_file "$(specification_coverage_file)" "$(project_decomposition_plan_file)" || return 1
	[[ "$(specification_coverage_verified_count)" == "$(specification_obligation_count)" ]]
}

project_is_blocked()
{
	[[ -f "$(project_block_file)" ]]
}

mark_project_awaiting_oracle()
{
	local task_id="$1" note_file="${2:-}" dir pending audit_id tmp
	oracle_enabled || return 0
	oracle_audit_budget_exhausted && return 0
	dir="$(project_oracle_dir)"
	mkdir -p "$dir"
	chmod 700 "$dir"
	pending="$(project_oracle_pending_file)"
	[[ -f "$pending" ]] && return 0
	audit_id=$(( $(find "$dir" -maxdepth 1 -name 'audit-*.md' -type f 2>/dev/null | wc -l) + 1 ))
	tmp="$pending.tmp.$$"
	{
		printf '# Oracle Audit Pending\n\n'
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Audit-ID: %s\n\n' "$audit_id"
		printf 'Triggered-By-Task: %s\n\n' "$task_id"
		printf 'Triggered-At: %s\n' "$(timestamp_utc)"
		if [[ -n "$note_file" ]]; then printf '\nTrigger-Review: %s\n' "$note_file"; fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$pending"
	log_event "ORACLE_AUDIT_PENDING audit_id=$audit_id task=$task_id"
}

project_plan_definition_file()
{
	printf '%s/control/project-plan.tsv' "$(project_dir)"
}

project_plan_state_file()
{
	printf '%s/control/project-plan-state.tsv' "$(project_dir)"
}

project_decomposition_plan_file()
{
	printf '%s/control/project-decomposition-v2.tsv' "$(project_dir)"
}

project_plan_uses_dag()
{
	[[ -f "$(project_decomposition_plan_file)" ]]
}

project_plan_node_value()
{
	local item_id="$1" field="$2"
	awk -F '\t' -v item="$item_id" -v wanted="$field" '
		function trim(value) {
			sub(/^[[:space:]]+/, "", value)
			sub(/[[:space:]]+$/, "", value)
			return value
		}
		NR == 1 {
			for (i = 1; i <= NF; i++) column[trim($i)] = i
			next
		}
		trim($1) == item && column[wanted] {print trim($column[wanted]); exit}
	' "$(project_decomposition_plan_file)"
}

project_plan_has_column()
{
	local field="$1"
	awk -F '\t' -v wanted="$field" 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == wanted) exit 0; exit 1}' \
		"$(project_decomposition_plan_file)"
}

project_plan_dependencies_satisfied()
{
	local item_id="$1" dependencies dependency status
	project_plan_uses_dag || return 0
	dependencies="$(project_plan_node_value "$item_id" depends_on)"
	[[ -n "$dependencies" && "$dependencies" != - ]] || return 0
	IFS=',' read -r -a dependency_list <<< "$dependencies"
	for dependency in "${dependency_list[@]}"; do
		status="$(project_plan_item_status "$dependency")"
		[[ "$status" == COMPLETE ]] || return 1
	done
}

project_plan_first_ready_item()
{
	local item_id status
	while IFS=$'\t' read -r item_id status _; do
		[[ -n "$item_id" && "$item_id" != \#* && "$status" == PENDING ]] || continue
		if project_plan_dependencies_satisfied "$item_id"; then
			printf '%s\n' "$item_id"
			return 0
		fi
	done < "$(project_plan_state_file)"
	return 1
}

project_plan_exists()
{
	[[ -f "$(project_plan_definition_file)" && -f "$(project_plan_state_file)" ]]
}

project_plan_total_count()
{
	local file
	file="$(project_plan_state_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	awk -F '\t' '!/^#/ && NF >= 4 {count++} END {print count + 0}' "$file"
}

project_plan_complete_count()
{
	local file item_id status count=0
	file="$(project_plan_state_file)"
	[[ -f "$file" ]] || { printf '0\n'; return 0; }
	while IFS=$'\t' read -r item_id status _; do
		[[ -n "$item_id" && "$item_id" != \#* && "$status" == COMPLETE ]] || continue
		project_plan_item_is_invalidated "$item_id" || count=$((count + 1))
	done < "$file"
	printf '%s\n' "$count"
}

project_plan_pending_count()
{
	local total complete
	total="$(project_plan_total_count)"
	complete="$(project_plan_complete_count)"
	printf '%s\n' "$((total - complete))"
}

project_plan_progress_percent()
{
	local total complete
	total="$(project_plan_total_count)"
	complete="$(project_plan_complete_count)"
	if (( total == 0 )); then
		printf '0\n'
	else
		printf '%s\n' "$((complete * 100 / total))"
	fi
}

project_plan_progress_percent_decimal()
{
	local total complete
	total="$(project_plan_total_count)"
	complete="$(project_plan_complete_count)"
	awk -v complete="$complete" -v total="$total" 'BEGIN {
		if (total == 0) printf "0.0\n";
		else printf "%.1f\n", complete * 100.0 / total;
	}'
}

project_plan_item_is_invalidated()
{
	local item_id="$1"
	compgen -G "$(plan_dependency_invalidation_dir)/$item_id--*.invalidated.md" >/dev/null ||
		[[ -f "$(plan_dependency_invalidation_file "$item_id")" ]]
}

project_plan_item_status()
{
	local item_id="$1"
	if project_plan_item_is_invalidated "$item_id"; then
		printf 'INVALIDATED\n'
		return 0
	fi
	awk -F '\t' -v item="$item_id" '!/^#/ && $1 == item {print $2; exit}' "$(project_plan_state_file)"
}

project_plan_item_root()
{
	local item_id="$1"
	awk -F '\t' -v item="$item_id" '!/^#/ && $1 == item {print $3; exit}' "$(project_plan_state_file)"
}

project_plan_item_for_root()
{
	local root="$1"
	awk -F '\t' -v root="$root" '!/^#/ && $3 == root {print $1; exit}' "$(project_plan_state_file)"
}

set_project_plan_item_waiting_dependency()
{
	local item_id="$1" root="$2" state status current_root tmp
	state="$(project_plan_state_file)"
	status="$(project_plan_item_status "$item_id")"
	current_root="$(project_plan_item_root "$item_id")"
	[[ "$status" == ACTIVE || "$status" == PENDING ]] ||
		die "project plan item cannot wait for a dependency from state $status: $item_id"
	if [[ "$status" == ACTIVE ]]; then
		[[ "$current_root" == "$root" ]] || die "active plan item belongs to root $current_root, not $root"
	else
		[[ "$current_root" == - ]] || die "pending plan item unexpectedly has a task root: $item_id"
	fi
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v root="$root" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "WAITING_DEPENDENCY"; $3 = root; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
}

publish_dependency_request()
{
	local request_id="$1" item_id="$2" root="$3" requirements_source="$4" note_source="$5" trigger_task="${6:--}"
	local dependency_dir request requirements root_marker tmp failures item_status
	validate_dependency_request_id "$request_id"
	validate_task_id "$root"
	item_status="$(project_plan_item_status "$item_id")"
	if [[ "$item_status" == PENDING ]]; then
		[[ "$root" == "$item_id" ]] ||
			die "pending dependency root must equal its project plan item ID: $item_id"
	else
		[[ "$(project_plan_item_for_root "$root")" == "$item_id" ]] ||
			die "task root $root is not assigned to project plan item $item_id"
	fi
	[[ -f "$note_source" && -s "$note_source" ]] || die 'dependency request note is missing or empty'
	validate_dependency_requirements_file "$requirements_source"
	dependency_requirements_satisfied "$requirements_source" &&
		die 'all declared dependencies are already satisfied; refusing a waiting transition'
	dependency_dir="$(dependency_request_dir)"
	mkdir -p "$dependency_dir"
	chmod 700 "$dependency_dir"
	request="$(dependency_request_file "$request_id")"
	requirements="$(dependency_requirements_file "$request_id")"
	[[ ! -e "$request" && ! -e "$requirements" ]] || die "dependency request already exists: $request_id"
	install -m 600 "$requirements_source" "$requirements"
	failures="$(dependency_requirement_failures "$requirements")"
	tmp="$request.tmp.$$"
	{
		printf '# Waiting Dependency Request\n\n'
		printf 'Request-ID: %s\n\n' "$request_id"
		printf 'Project: %s\n\n' "$PROJECT"
		printf 'Plan-Item: %s\n\n' "$item_id"
		printf 'Task-Root: %s\n\n' "$root"
		printf 'Triggered-By-Task: %s\n\n' "$trigger_task"
		printf 'Consumer-Repository: %s\n\n' "$REPOSITORY"
		printf 'Requirements-File: %s\n\n' "$requirements"
		printf 'Waiting-Since: %s\n\n' "$(timestamp_utc)"
		printf 'Dependency-Fingerprint: sha256:%s\n\n' "$(sha256sum "$requirements" | awk '{print $1}')"
		printf '## Unsatisfied requirements\n\n```text\n%s\n```\n\n' "$failures"
		printf '## Agent-authored dependency specification\n\n'
		cat "$note_source"
		printf '\n\n## Supply protocol\n\n'
		printf 'A producer must publish the requested source-only commit and any requested branch, then supply each dependency with `harness-supply-dependency ENV_FILE REQUEST_ID DEPENDENCY_ID SOURCE_REPOSITORY [SOURCE_REF]`. The consumer wakes only after every commit/ref, ancestry constraint, and required path validates.\n'
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$request"
	set_project_plan_item_waiting_dependency "$item_id" "$root"
	root_marker="$(task_root_waiting_dependency_file "$root")"
	{
		printf '# Root Waiting For Dependency\n\n'
		printf 'Project: %s\n\nTask-Root: %s\n\nPlan-Item: %s\n\nRequest-ID: %s\n\n' \
			"$PROJECT" "$root" "$item_id" "$request_id"
		printf 'Dependency-Specification: %s\n\nRequirements-File: %s\n\n' "$request" "$requirements"
		printf 'Paused-At: %s\n\n' "$(timestamp_utc)"
		printf 'This state consumes no worker or manager review cycles and records no durable implementation gain.\n'
	} > "$root_marker.tmp.$$"
	chmod 600 "$root_marker.tmp.$$"
	mv "$root_marker.tmp.$$" "$root_marker"
	log_event "WAITING_DEPENDENCY request=$request_id item=$item_id root=$root trigger_task=$trigger_task requirements=$requirements"
	printf '%s\n' "$request"
}

resolve_dependency_request_if_ready()
{
	local request="$1" request_id requirements item_id root state tmp archive
	[[ -f "$request" ]] || return 1
	request_id="$(metadata_value "$request" Request-ID)"
	requirements="$(metadata_value "$request" Requirements-File)"
	item_id="$(metadata_value "$request" Plan-Item)"
	root="$(metadata_value "$request" Task-Root)"
	[[ -f "$requirements" ]] || return 1
	dependency_requirements_satisfied "$requirements" || return 1
	state="$(project_plan_state_file)"
	[[ "$(project_plan_item_status "$item_id")" == WAITING_DEPENDENCY ]] || return 1
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "ACTIVE"; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
	rm -f "$(task_root_waiting_dependency_file "$root")"
	archive="$(dependency_request_dir)/$request_id.resolved.md"
	{
		cat "$request"
		printf '\n\nResolved-At: %s\n' "$(timestamp_utc)"
	} > "$archive.tmp.$$"
	chmod 600 "$archive.tmp.$$"
	mv "$archive.tmp.$$" "$archive"
	rm -f "$request"
	log_event "DEPENDENCY_RESOLVED request=$request_id item=$item_id root=$root requirements=$requirements"
	return 0
}

project_plan_all_complete()
{
	local total pending
	project_plan_exists || return 1
	total="$(project_plan_total_count)"
	pending="$(project_plan_pending_count)"
	(( total > 0 && pending == 0 ))
}

root_accepted_task_file()
{
	local root="$1"
	local file task
	shopt -s nullglob
	for file in "$(project_dir)/archive/$PROJECT-task-$root.accepted.md" \
		"$(project_dir)/archive/$PROJECT-task-$root-revision-"*.accepted.md; do
		[[ -f "$file" ]] || continue
		task="${file##*/}"
		task="${task#${PROJECT}-task-}"
		task="${task%.accepted.md}"
		if [[ "$(task_root_id "$task")" == "$root" ]]; then
			printf '%s\n' "$file"
			return 0
		fi
	done
	return 1
}

root_has_accepted_task()
{
	root_accepted_task_file "$1" >/dev/null
}

initialize_project_plan()
{
	local source_file="$1" coverage_source="${2:-}"
	local definition state definition_tmp state_tmp item_id title accepted_root extra
	local seen_file
	[[ -f "$source_file" ]] || die "project plan source does not exist: $source_file"
	! project_plan_exists || die "project plan already exists: $(project_plan_definition_file)"
	if (( HARNESS_DECOMPOSITION_V2 == 1 )); then
		initialize_project_plan_v2 "$source_file" "$coverage_source"
		return
	fi
	definition="$(project_plan_definition_file)"
	state="$(project_plan_state_file)"
	definition_tmp="$definition.tmp.$$"
	state_tmp="$state.tmp.$$"
	seen_file="$state.seen.$$"
	: > "$seen_file"
	{
		printf '# coding-harness-project-plan-v1\n'
		printf '# project=%s\n' "$PROJECT"
		printf '# specification=%s\n' "$SPECIFICATION"
		if [[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]]; then
			printf '# specification_sha256=%s\n' "$(sha256sum "$SPECIFICATION" | awk '{print $1}')"
		fi
		printf '# created_at=%s\n' "$(timestamp_utc)"
	} > "$definition_tmp"
	{
		printf '# coding-harness-project-plan-state-v1\n'
		printf '# item_id\tstatus\ttask_root\tupdated_at\n'
	} > "$state_tmp"
	while IFS=$'\t' read -r item_id title accepted_root extra || [[ -n "${item_id:-}${title:-}${accepted_root:-}${extra:-}" ]]; do
		[[ -n "${item_id:-}" ]] || continue
		[[ "$item_id" != \#* ]] || continue
		[[ -z "${extra:-}" ]] || die "project plan item has more than three tab-separated fields: $item_id"
		[[ "$item_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid project plan item ID: $item_id"
		[[ -n "${title:-}" ]] || die "project plan item has no title: $item_id"
		! grep -Fqx -- "$item_id" "$seen_file" || die "duplicate project plan item ID: $item_id"
		printf '%s\n' "$item_id" >> "$seen_file"
		printf '%s\t%s\n' "$item_id" "$title" >> "$definition_tmp"
		if [[ -n "${accepted_root:-}" && "$accepted_root" != '-' ]]; then
			validate_task_id "$accepted_root"
			[[ "$(task_root_id "$accepted_root")" == "$accepted_root" ]] || die "accepted project plan task must be a root ID: $accepted_root"
			root_has_accepted_task "$accepted_root" || die "cannot reconcile project plan item $item_id; no accepted task exists for root $accepted_root"
			[[ "$(task_progress_percent "$accepted_root")" == 100 ]] || die "cannot reconcile project plan item $item_id; root $accepted_root is not at 100%"
			printf '%s\tCOMPLETE\t%s\t%s\n' "$item_id" "$accepted_root" "$(timestamp_utc)" >> "$state_tmp"
		else
			printf '%s\tPENDING\t-\t%s\n' "$item_id" "$(timestamp_utc)" >> "$state_tmp"
		fi
	done < "$source_file"
	rm -f "$seen_file"
	(( $(awk -F '\t' '!/^#/ && NF == 2 {count++} END {print count + 0}' "$definition_tmp") > 0 )) || die 'project plan must contain at least one item'
	chmod 600 "$definition_tmp" "$state_tmp"
	mv "$definition_tmp" "$definition"
	mv "$state_tmp" "$state"
	log_event "PROJECT_PLAN_INITIALIZED items=$(project_plan_total_count) complete=$(project_plan_complete_count) file=$definition"
	trace_event PROJECT_PLAN_INITIALIZED "items=$(project_plan_total_count)" "complete=$(project_plan_complete_count)" "definition_file=$definition" "state_file=$state"
}

decomposition_complexity_header()
{
	printf '%s\n' $'node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\tfocused_validation\tallowed_paths\trequired_symbols\tleaf_type\tcomplexity_class\tworker_route\tbehavioral_concerns\tfailure_paths\townership_transitions\tconcurrency_boundaries\tvalidation_surfaces\timplementation_files\tpredicted_worker_actions\tpredicted_p95_tokens\tterra_exception'
}

decomposition_typed_header()
{
	printf '%s\n' $'node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\tfocused_validation\tallowed_paths\trequired_symbols\tleaf_type\tcomplexity_class\tworker_route'
}

decomposition_has_complexity_contract()
{
	local header
	IFS= read -r header < "$1" || return 1
	[[ "$header" == "$(decomposition_complexity_header)" ]]
}

validate_decomposition_measured_schema_file()
{
	local dag="$1" node_id leaf_type complexity_class worker_route errors=0 index value
	local -a fields=()
	while IFS=$'\t' read -r -a fields; do
		node_id="${fields[0]:-}"
		[[ "$node_id" != node_id && -n "$node_id" ]] || continue
		if (( ${#fields[@]} != 20 )); then
			printf 'LUNA_COMPLEXITY_INVALID node=%s row must contain exactly 20 fields\n' "$node_id"
			errors=$((errors + 1))
			continue
		fi
		leaf_type="${fields[8]}"; complexity_class="${fields[9]}"; worker_route="${fields[10]}"
		if [[ ! "$leaf_type" =~ ^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION|VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$ ]]; then
			printf 'LUNA_COMPLEXITY_INVALID node=%s has non-executable leaf_type=%s; every DAG row must be an executable Luna or Terra leaf, never a planner/grouping node\n' "$node_id" "$leaf_type"
			errors=$((errors + 1))
		fi
		if [[ ! "$complexity_class" =~ ^(LOW|MEDIUM|HIGH)$ ]]; then
			printf 'LUNA_COMPLEXITY_INVALID node=%s has invalid complexity_class=%s\n' "$node_id" "$complexity_class"
			errors=$((errors + 1))
		fi
		if [[ ! "$worker_route" =~ ^(LUNA|TERRA)$ ]]; then
			printf 'LUNA_COMPLEXITY_INVALID node=%s has non-executable worker_route=%s; Sol decomposes but never executes DAG rows\n' "$node_id" "$worker_route"
			errors=$((errors + 1))
		fi
		if [[ "${HARNESS_MODEL_POLICY:-legacy}" == luna_only && "$worker_route" != LUNA ]]; then
			printf 'LUNA_ONLY_ROUTE_INVALID node=%s worker_route=%s; recursively decompose this boundary into Luna-executable children\n' "$node_id" "$worker_route"
			errors=$((errors + 1))
		fi
		for index in 11 12 13 14 15 16 17 18; do
			value="${fields[$index]}"
			if [[ ! "$value" =~ ^[0-9]+$ ]]; then
				printf 'LUNA_COMPLEXITY_INVALID node=%s dimension_%s=%s must be a nonnegative integer\n' "$node_id" "$((index + 1))" "$value"
				errors=$((errors + 1))
			fi
		done
		for index in 11 15 16 17 18; do
			value="${fields[$index]}"
			if (( index == 16 )) && [[ "$value" == 0 ]]; then
				if [[ "$leaf_type" =~ ^(VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$ ]]; then
					continue
				fi
				printf 'LUNA_COMPLEXITY_INVALID node=%s implementation files may be zero only for zero-write verification or Terra decision/integration leaves\n' "$node_id"
				errors=$((errors + 1))
				continue
			fi
			if [[ "$value" =~ ^[0-9]+$ ]] && (( value == 0 )); then
				printf 'LUNA_COMPLEXITY_INVALID node=%s dimension_%s must be positive\n' "$node_id" "$((index + 1))"
				errors=$((errors + 1))
			fi
		done
	done < "$dag"
	(( errors == 0 ))
}

decomposition_complexity_report_file()
{
	printf '%s/control/decomposition-complexity.tsv\n' "$(project_dir)"
}

complexity_contract_sha256()
{
	printf '%s\n' \
		'node-local-risk-domains-v2' 'accepted-success-only-calibration-v1' \
		"$HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF" "$HARNESS_MAX_LUNA_ALLOWED_PATHS" \
		"$HARNESS_MAX_LUNA_REQUIRED_SYMBOLS" "$HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS" \
		"$HARNESS_MAX_LUNA_FAILURE_PATHS" "$HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS" \
		"$HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES" "$HARNESS_MAX_LUNA_VALIDATION_SURFACES" \
		"$HARNESS_MAX_LUNA_IMPLEMENTATION_FILES" "$HARNESS_MAX_LUNA_PREDICTED_ACTIONS" \
		"$HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS" \
		"$HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS" "$HARNESS_MAX_LUNA_COMPLEXITY_SCORE" \
		"$HARNESS_MAX_LUNA_RISK_DOMAINS" "$HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT" \
		"$HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES" "$LUNA_WORKER_MODEL" | sha256sum | awk '{print $1}'
}

complexity_calibrated_tokens_per_score()
{
	local model="$1" observations outcomes samples rate_file
	rate_file="$(mktemp)"
	while IFS= read -r observations; do
		outcomes="${observations%/complexity-observations.tsv}/complexity-outcomes.tsv"
		[[ -f "$outcomes" ]] || continue
		awk -F '\t' -v model="$model" '
			NR==FNR {if(FNR>1 && $5=="ACCEPTED") accepted[$2 SUBSEP $4]=1; next}
			FNR > 1 && accepted[$2 SUBSEP $4] && $6 == model && $21 == "success" &&
				$8 ~ /^[1-9][0-9]*$/ && $11 ~ /^[1-9][0-9]*$/ {
				print int(($11 + $8 - 1) / $8)
			}
		' "$outcomes" "$observations" >> "$rate_file"
	done < <(find "$HARNESS_ROOT/projects" -mindepth 3 -maxdepth 3 -type f \
		-path '*/logs/complexity-observations.tsv' 2>/dev/null | sort)
	samples="$(awk 'END {print NR+0}' "$rate_file")"
	if (( samples < HARNESS_COMPLEXITY_CALIBRATION_MIN_SAMPLES )); then
		rm -f "$rate_file"
		printf '%s\n' "$HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT"
		return 0
	fi
	sort -n "$rate_file" -o "$rate_file"
	# Nearest-rank p95. Calibration may make the contract stricter, never looser
	# than the configured cold-start estimate.
	rate="$(awk -v rank="$(( (95 * samples + 99) / 100 ))" 'NR == rank {print; exit}' "$rate_file")"
	rm -f "$rate_file"
	[[ "$rate" =~ ^[1-9][0-9]*$ ]] || rate="$HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT"
	(( rate >= HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT )) || rate="$HARNESS_COMPLEXITY_TOKENS_PER_SCORE_POINT"
	printf '%s\n' "$rate"
}

write_decomposition_complexity_report()
{
	local dag="$1" coverage="$2" output="$3" obligations_file calibration_rate
	local node_id route leaf paths symbols behavioral failures ownership concurrency validations implementation_files actions declared_p95 exception
	local obligation_count obligation_weight path_count symbol_count risk_domains score calibrated_p95 effective_p95 status violations text
	local derived derived_behavioral derived_failures derived_ownership derived_concurrency derived_validations obligation_text
	local -a fields=()
	decomposition_has_complexity_contract "$dag" || return 2
	obligations_file="$(specification_obligations_file)"
	calibration_rate="$(complexity_calibrated_tokens_per_score "$LUNA_WORKER_MODEL")"
	printf '%s\n' $'node_id\tworker_route\tleaf_type\tcomplexity_score\tobligations\tobligation_weight\tallowed_paths\trequired_symbols\tbehavioral_concerns\tfailure_paths\townership_transitions\tconcurrency_boundaries\tvalidation_surfaces\timplementation_files\tpredicted_worker_actions\tdeclared_p95_tokens\teffective_p95_tokens\trisk_domains\tstatus\tviolations' > "$output"
	# Validate every declared vector before arithmetic. Reporting the complete
	# defect set prevents one paid Sol repair turn per malformed row.
	if ! awk -F '\t' '
		NR == 1 {next}
		NF != 20 {
			printf "LUNA_COMPLEXITY_INVALID row=%d node=%s does not contain 20 fields\n", NR, ($1 == "" ? "-" : $1) > "/dev/stderr"
			errors++
			next
		}
		{
			for (column = 12; column <= 19; column++) {
				if ($column !~ /^[0-9]+$/) {
					printf "LUNA_COMPLEXITY_INVALID node=%s field=%d requires a nonnegative integer\n", $1, column > "/dev/stderr"
					errors++
			}
			}
			zero_write = ($9 ~ /^(VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$/)
			if ($12 !~ /^[1-9][0-9]*$/ || $16 !~ /^[1-9][0-9]*$/ ||
				(zero_write ? $17 !~ /^[0-9]+$/ : $17 !~ /^[1-9][0-9]*$/) || $18 !~ /^[1-9][0-9]*$/ ||
				$19 !~ /^[1-9][0-9]*$/) {
				printf "LUNA_COMPLEXITY_INVALID node=%s requires positive behavioral, validation, action, and token predictions; implementation files may be zero only for zero-write verification or Terra decision/integration leaves\n", $1 > "/dev/stderr"
				errors++
			}
		}
		END {exit errors > 0 ? 1 : 0}
	' "$dag"; then
		return 1
	fi
	while IFS=$'\t' read -r -a fields; do
		(( ${#fields[@]} == 20 )) || { printf 'LUNA_COMPLEXITY_INVALID row does not contain 20 fields\n' >&2; return 1; }
		node_id="${fields[0]}"; paths="${fields[6]}"; symbols="${fields[7]}"; leaf="${fields[8]}"; route="${fields[10]}"
		behavioral="${fields[11]}"; failures="${fields[12]}"; ownership="${fields[13]}"; concurrency="${fields[14]}"
		validations="${fields[15]}"; implementation_files="${fields[16]}"; actions="${fields[17]}"; declared_p95="${fields[18]}"; exception="${fields[19]}"
		for value in "$behavioral" "$failures" "$ownership" "$concurrency" "$validations" "$implementation_files" "$actions" "$declared_p95"; do
			[[ "$value" =~ ^[0-9]+$ ]] || { printf 'LUNA_COMPLEXITY_INVALID node=%s requires nonnegative integer dimensions\n' "$node_id" >&2; return 1; }
		done
		if ! (( behavioral > 0 && validations > 0 && actions > 0 && declared_p95 > 0 )) ||
			{ (( implementation_files == 0 )) &&
				[[ ! "$leaf" =~ ^(VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$ ]]; }; then
			printf 'LUNA_COMPLEXITY_INVALID node=%s requires positive behavioral, validation, action, and token predictions; implementation files may be zero only for zero-write verification or Terra decision/integration leaves\n' "$node_id" >&2
			return 1
		fi
		if (( implementation_files > 0 && actions < HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS )); then
			actions="$HARNESS_MIN_SOURCE_CHANGE_AGENT_ACTIONS"
		fi
		path_count="$(awk -F, '{if ($0=="-" || $0=="") print 0; else print NF}' <<< "$paths")"
		symbol_count="$(awk -F, '{if ($0=="-" || $0=="") print 0; else print NF}' <<< "$symbols")"
		obligation_count="$(awk -F '\t' -v wanted="$node_id" 'NR>1 {n=split($2,a,","); for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i]); if(a[i]==wanted){c++; break}}} END{print c+0}' "$coverage")"
		obligation_weight="$(awk -F '\t' -v wanted="$node_id" -v coverage="$coverage" '
			BEGIN {while ((getline line < coverage)>0) {split(line,c,"\t"); n=split(c[2],a,","); for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i]); if(a[i]==wanted) selected[c[1]]=1}}}
			NR>1 && ($1 in selected) {w=2; if($5=="CONTRACT"||$5=="INVARIANT"||$5=="PERFORMANCE")w=3; else if($5=="INTEGRATION"||$5=="RESOURCE_LIFETIME")w=4; else if($5=="TEST"||$5=="DOCUMENTATION"||$5=="COMPLETION")w=1; total+=w}
			END{print total+0}
		' "$obligations_file")"
		derived="$(awk -F '\t' -v wanted="$node_id" -v coverage="$coverage" '
			BEGIN {while ((getline line < coverage)>0) {split(line,c,"\t"); n=split(c[2],a,","); for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i]); if(a[i]==wanted) selected[c[1]]=1}}}
			NR>1 && ($1 in selected) {
				tolower_text=tolower($5 " " $6 " " $7); corpus=corpus " " tolower_text
				if($5 ~ /^(FUNCTIONAL|CONTRACT|INTEGRATION|INTERFACE)$/) behavior++
				if(tolower_text ~ /(fail|error|invalid|negative|overflow|rollback|unchanged|atomic)/) failure++
				if(tolower_text ~ /(owner|ownership|publication|publish|lifetime|cleanup)/) ownership++
				if(tolower_text ~ /(concurr|parallel|enqueue|synchron|multi-device|multidevice|shard|ordering)/) concurrency++
				if($5 ~ /^(TEST|VALIDATION|COMPLETION)$/) validation++
			}
			END {gsub(/[[:space:]]+/," ",corpus); printf "%d\t%d\t%d\t%d\t%d\t%s\n",behavior+0,failure+0,ownership+0,concurrency+0,validation+0,corpus}
		' "$obligations_file")"
		IFS=$'\t' read -r derived_behavioral derived_failures derived_ownership derived_concurrency derived_validations obligation_text <<< "$derived"
		(( behavioral >= derived_behavioral )) || behavioral="$derived_behavioral"
		(( failures >= derived_failures )) || failures="$derived_failures"
		(( ownership >= derived_ownership )) || ownership="$derived_ownership"
		(( concurrency >= derived_concurrency )) || concurrency="$derived_concurrency"
		(( validations >= derived_validations )) || validations="$derived_validations"
		# Complexity is measured at the executable child boundary.  The complete
		# normalized obligation remains authoritative for coverage and derived
		# minimum dimensions above, but reattaching all of its semantic risk words
		# to every child would make a broad obligation mathematically impossible to
		# decompose: each child would inherit the parent's full risk-domain count.
		text="$(printf '%s %s %s' "${fields[3]}" "${fields[4]}" "${fields[5]}" | tr '[:upper:]' '[:lower:]')"
		risk_domains=0
		grep -Eq 'concurr|parallel|enqueue|synchron|multi-device|multidevice|shard' <<< "$text" && risk_domains=$((risk_domains + 1))
		grep -Eq 'owner|ownership|route|routing|publication|publish' <<< "$text" && risk_domains=$((risk_domains + 1))
		grep -Eq 'cleanup|allocate|allocation|free|lifetime|resource' <<< "$text" && risk_domains=$((risk_domains + 1))
		grep -Eq 'failure|failed|error|rollback|unchanged|atomic' <<< "$text" && risk_domains=$((risk_domains + 1))
		grep -Eq 'telemetry|receipt|observability|metric' <<< "$text" && risk_domains=$((risk_domains + 1))
		score=$((obligation_weight + behavioral * 3 + failures * 2 + ownership * 3 + concurrency * 4 + validations * 2 + implementation_files + (symbol_count + 1) / 2))
		calibrated_p95=$((score * calibration_rate))
		effective_p95="$declared_p95"
		(( effective_p95 >= calibrated_p95 )) || effective_p95="$calibrated_p95"
		status=READY
		violations="-"
		if [[ "$route" == LUNA ]]; then
			[[ "$exception" == - ]] || violations="terra_exception=$exception"
			for check in \
				"obligations:$obligation_count:$HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF" \
				"allowed_paths:$path_count:$HARNESS_MAX_LUNA_ALLOWED_PATHS" \
				"required_symbols:$symbol_count:$HARNESS_MAX_LUNA_REQUIRED_SYMBOLS" \
				"behavioral_concerns:$behavioral:$HARNESS_MAX_LUNA_BEHAVIORAL_CONCERNS" \
				"failure_paths:$failures:$HARNESS_MAX_LUNA_FAILURE_PATHS" \
				"ownership_transitions:$ownership:$HARNESS_MAX_LUNA_OWNERSHIP_TRANSITIONS" \
				"concurrency_boundaries:$concurrency:$HARNESS_MAX_LUNA_CONCURRENCY_BOUNDARIES" \
				"validation_surfaces:$validations:$HARNESS_MAX_LUNA_VALIDATION_SURFACES" \
				"implementation_files:$implementation_files:$HARNESS_MAX_LUNA_IMPLEMENTATION_FILES" \
				"predicted_worker_actions:$actions:$HARNESS_MAX_LUNA_PREDICTED_ACTIONS" \
				"effective_p95_tokens:$effective_p95:$HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS" \
				"complexity_score:$score:$HARNESS_MAX_LUNA_COMPLEXITY_SCORE" \
				"risk_domains:$risk_domains:$HARNESS_MAX_LUNA_RISK_DOMAINS"; do
				IFS=: read -r name actual maximum <<< "$check"
				if (( actual > maximum )); then
					[[ "$violations" == - ]] && violations="" || violations+=";"
					violations+="$name=$actual>$maximum"
				fi
			done
			[[ "$violations" == - ]] || status=OVER_BUDGET
		elif [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			status=LUNA_ONLY_ROUTE_INVALID
			violations="worker_route=$route"
		else
			[[ "$exception" =~ ^(CONTRACT_DECISION|ARCHITECTURE_DECISION|CONCURRENCY_DESIGN|AMBIGUOUS_SPECIFICATION|UNEXPLAINED_INTEGRATION|IRREDUCIBLE_CROSS_BOUNDARY)$ ]] || {
				status=INVALID_TERRA_EXCEPTION
				violations="terra_exception=$exception"
			}
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$node_id" "$route" "$leaf" "$score" "$obligation_count" "$obligation_weight" "$path_count" "$symbol_count" \
			"$behavioral" "$failures" "$ownership" "$concurrency" "$validations" "$implementation_files" "$actions" \
			"$declared_p95" "$effective_p95" "$risk_domains" "$status" "$violations" >> "$output"
	done < <(tail -n +2 "$dag")
	chmod 600 "$output"
	if awk -F '\t' 'NR>1 && $19!="READY" {found=1} END{exit found?0:1}' "$output"; then
		if [[ "$HARNESS_MODEL_POLICY" == luna_only ]]; then
			awk -F '\t' 'NR>1 && $19!="READY" {printf "LUNA_COMPLEXITY_OVER_BUDGET node=%s route=%s score=%s status=%s violations=%s; recursively decompose into Luna-executable children\n",$1,$2,$4,$19,$20 > "/dev/stderr"}' "$output"
		else
			awk -F '\t' 'NR>1 && $19!="READY" {printf "LUNA_COMPLEXITY_OVER_BUDGET node=%s route=%s score=%s status=%s violations=%s; continue recursive Sol decomposition or justify an irreducible Terra boundary\n",$1,$2,$4,$19,$20 > "/dev/stderr"}' "$output"
		fi
		return 1
	fi
}

initialize_project_plan_v2()
{
	local source_file="$1" coverage_source="${2:-}" header expected_header complexity_header legacy_header definition state dag coverage complexity_report
	local definition_tmp state_tmp dag_tmp coverage_tmp complexity_tmp seen_file
	local node_id parent_id depends_on deliverable acceptance_evidence focused_validation field_index
	local allowed_paths required_symbols leaf_type complexity_class worker_route dependency
	local node_count luna_count luna_percent coding_count luna_coding_count luna_coding_percent has_leaf_type=0 has_complexity=0 route_column=11 type_column=9
	local obligations_for_node provenance provenance_tmp route_violations zero_write_scope
	local -a fields=()
	expected_header="$(decomposition_typed_header)"
	complexity_header="$(decomposition_complexity_header)"
	legacy_header=$'node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\tfocused_validation\tallowed_paths\trequired_symbols\tcomplexity_class\tworker_route'
	IFS= read -r header < "$source_file" || die 'decomposition DAG is empty'
	if [[ "$header" == "$complexity_header" ]]; then
		has_leaf_type=1
		has_complexity=1
	elif [[ "$header" == "$expected_header" ]]; then
		has_leaf_type=1
	elif [[ "$header" == "$legacy_header" ]]; then
		route_column=10
		[[ "$HARNESS_PREFERRED_WORKER_ROUTE" != LUNA ]] ||
			die "Luna-preferred decomposition requires the leaf_type column: $expected_header"
	else
		die "decomposition DAG header must be: $complexity_header"
	fi
	if (( has_leaf_type == 1 )) && [[ "$HARNESS_PREFERRED_WORKER_ROUTE" == LUNA ]]; then
		route_violations="$(awk -F '\t' '
			NR > 1 && $11 == "TERRA" && $9 ~ /^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION|VERIFICATION_ONLY)$/ {
				printf "Luna-preferred DAG routes coding node %s to Terra; split it until it is LOW/LUNA or use an irreducible Terra integration boundary\n", $1
			}
		' "$source_file")"
		if [[ -n "$route_violations" ]]; then
			printf 'ERROR: decomposition route contract has multiple or unresolved defects:\n%s\n' "$route_violations" >&2
			return 1
		fi
	fi
	definition="$(project_plan_definition_file)"
	state="$(project_plan_state_file)"
	dag="$(project_decomposition_plan_file)"
	coverage="$(specification_coverage_file)"
	complexity_report="$(decomposition_complexity_report_file)"
	definition_tmp="$definition.tmp.$$"
	state_tmp="$state.tmp.$$"
	dag_tmp="$dag.tmp.$$"
	coverage_tmp="$coverage.tmp.$$"
	complexity_tmp="$complexity_report.tmp.$$"
	seen_file="$state.seen.$$"
	: > "$seen_file"
	printf '%s\n' "$header" > "$dag_tmp"
	{
		printf '# coding-harness-project-plan-v2\n'
		printf '# project=%s\n' "$PROJECT"
		printf '# specification=%s\n' "$SPECIFICATION"
		if [[ -n "$SPECIFICATION" && -f "$SPECIFICATION" ]]; then
			printf '# specification_sha256=%s\n' "$(sha256sum "$SPECIFICATION" | awk '{print $1}')"
		fi
		printf '# created_at=%s\n' "$(timestamp_utc)"
	} > "$definition_tmp"
	{
		printf '# coding-harness-project-plan-state-v2\n'
		printf '# item_id\tstatus\ttask_root\tupdated_at\n'
	} > "$state_tmp"
	while IFS=$'\t' read -r -a fields; do
		if (( has_leaf_type == 1 )); then
			if (( has_complexity == 1 )); then
				(( ${#fields[@]} == 20 )) || die 'each measured decomposition node must contain exactly twenty tab-separated fields'
			else
				(( ${#fields[@]} == 11 )) || die 'each decomposition node must contain exactly eleven tab-separated fields'
			fi
			for field_index in "${!fields[@]}"; do
				fields[$field_index]="$(trim_surrounding_whitespace "${fields[$field_index]}")"
			done
			node_id="${fields[0]}"; parent_id="${fields[1]}"; depends_on="${fields[2]}"
			deliverable="${fields[3]}"; acceptance_evidence="${fields[4]}"; focused_validation="${fields[5]}"
			allowed_paths="${fields[6]}"; required_symbols="${fields[7]}"; leaf_type="${fields[8]}"
			complexity_class="${fields[9]}"; worker_route="${fields[10]}"
		else
			(( ${#fields[@]} == 10 )) || die 'each legacy decomposition node must contain exactly ten tab-separated fields'
			for field_index in "${!fields[@]}"; do
				fields[$field_index]="$(trim_surrounding_whitespace "${fields[$field_index]}")"
			done
			node_id="${fields[0]}"; parent_id="${fields[1]}"; depends_on="${fields[2]}"
			deliverable="${fields[3]}"; acceptance_evidence="${fields[4]}"; focused_validation="${fields[5]}"
			allowed_paths="${fields[6]}"; required_symbols="${fields[7]}"; leaf_type=""
			complexity_class="${fields[8]}"; worker_route="${fields[9]}"
		fi
		[[ -n "$node_id" ]] || continue
		[[ "$node_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid decomposition node ID: $node_id"
		! grep -Fqx -- "$node_id" "$seen_file" || die "duplicate decomposition node ID: $node_id"
		[[ "$parent_id" == - || "$parent_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid parent ID for $node_id: $parent_id"
		if [[ "$parent_id" != - ]]; then
			grep -Fqx -- "$parent_id" "$seen_file" || die "parent must precede child $node_id: $parent_id"
		fi
		[[ -n "$depends_on" ]] || die "decomposition node has empty depends_on: $node_id"
		if [[ "$depends_on" != - ]]; then
			IFS=',' read -r -a dependency_list <<< "$depends_on"
			for dependency in "${dependency_list[@]}"; do
				[[ "$dependency" != "$node_id" ]] || die "node depends on itself: $node_id"
				grep -Fqx -- "$dependency" "$seen_file" ||
					die "dependency must precede node $node_id: $dependency"
			done
		fi
		[[ -n "$deliverable" && -n "$acceptance_evidence" && -n "$focused_validation" ]] ||
			die "node $node_id requires deliverable, acceptance_evidence, and focused_validation"
		architecture_require_scoped_validation "plan node $node_id focused_validation" "$focused_validation"
		if [[ -z "$allowed_paths" || "$allowed_paths" == - ]]; then
			zero_write_scope=0
			if (( has_leaf_type == 1 )) &&
				[[ "$leaf_type" =~ ^(VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$ ]]; then
				if (( has_complexity == 0 )) || [[ "${fields[16]}" == 0 ]]; then
					zero_write_scope=1
				fi
			fi
			(( zero_write_scope == 1 )) || die "node $node_id requires explicit allowed_paths"
		fi
		[[ -n "$required_symbols" ]] || die "node $node_id requires required_symbols or '-'"
		if (( has_leaf_type == 1 )); then
			[[ "$leaf_type" =~ ^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION|VERIFICATION_ONLY|CONTRACT_DESIGN|CROSS_COMPONENT_ARCHITECTURE|CONCURRENCY_PROTOCOL|INTEGRATION|AMBIGUOUS_SPECIFICATION)$ ]] ||
				die "invalid leaf_type for $node_id: $leaf_type"
		fi
		[[ "$complexity_class" =~ ^(LOW|MEDIUM|HIGH)$ ]] || die "invalid complexity_class for $node_id: $complexity_class"
		[[ "$worker_route" =~ ^(LUNA|TERRA)$ ]] || die "invalid worker_route for $node_id: $worker_route"
		[[ "$HARNESS_MODEL_POLICY" != luna_only || "$worker_route" == LUNA ]] ||
			die "Luna-only decomposition cannot install worker_route $worker_route for $node_id"
		[[ "$worker_route" != LUNA || "$complexity_class" == LOW ]] ||
			die "Luna node $node_id must have complexity_class LOW"
		if (( has_leaf_type == 1 )) && [[ "$worker_route" == LUNA ]]; then
			[[ "$leaf_type" =~ ^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION|VERIFICATION_ONLY)$ ]] ||
				die "Luna node $node_id has Terra-only leaf_type $leaf_type"
		fi
		printf '%s\n' "$node_id" >> "$seen_file"
		printf '%s\t%s\n' "$node_id" "$deliverable" >> "$definition_tmp"
		printf '%s\tPENDING\t-\t%s\n' "$node_id" "$(timestamp_utc)" >> "$state_tmp"
		if (( has_leaf_type == 1 )); then
			(IFS=$'\t'; printf '%s\n' "${fields[*]}") >> "$dag_tmp"
		else
			printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
				"$node_id" "$parent_id" "$depends_on" "$deliverable" "$acceptance_evidence" \
				"$focused_validation" "$allowed_paths" "$required_symbols" "$complexity_class" "$worker_route" >> "$dag_tmp"
		fi
	done < <(tail -n +2 "$source_file")
	rm -f "$seen_file"
	node_count="$(awk -F '\t' 'NR > 1 {count++} END {print count + 0}' "$dag_tmp")"
	(( node_count > 0 )) || die 'decomposition DAG must contain at least one node'
	luna_count="$(awk -F '\t' -v route="$route_column" 'NR > 1 && $route == "LUNA" {count++} END {print count + 0}' "$dag_tmp")"
	luna_percent=$((luna_count * 100 / node_count))
	if (( has_leaf_type == 1 )); then
		coding_count="$(awk -F '\t' -v type="$type_column" 'NR > 1 && $type ~ /^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION)$/ {count++} END {print count + 0}' "$dag_tmp")"
		luna_coding_count="$(awk -F '\t' -v type="$type_column" -v route="$route_column" 'NR > 1 && $type ~ /^(LOCAL_IMPLEMENTATION|TEST_IMPLEMENTATION|MECHANICAL_API|FOCUSED_BUG|DOCUMENTATION)$/ && $route == "LUNA" {count++} END {print count + 0}' "$dag_tmp")"
		if (( coding_count == 0 )); then luna_coding_percent=100; else luna_coding_percent=$((luna_coding_count * 100 / coding_count)); fi
		(( luna_coding_percent >= HARNESS_MIN_LUNA_CODING_NODE_PERCENT )) ||
			die "decomposition DAG routes only $luna_coding_count/$coding_count coding-eligible nodes ($luna_coding_percent%) to Luna; minimum is $HARNESS_MIN_LUNA_CODING_NODE_PERCENT%"
	else
		(( luna_percent >= HARNESS_MIN_LUNA_NODE_PERCENT )) ||
			die "legacy decomposition DAG routes only $luna_count/$node_count nodes ($luna_percent%) to Luna; minimum is $HARNESS_MIN_LUNA_NODE_PERCENT%"
	fi
	if specification_ir_available; then
		[[ -n "$coverage_source" ]] || die 'normalized specification DAG requires a coverage file'
		validate_specification_coverage_file "$coverage_source" "$dag_tmp"
		if (( has_leaf_type == 1 )); then
			while IFS=$'\t' read -r -a fields; do
				[[ "${fields[10]:-}" == LUNA ]] || continue
				node_id="${fields[0]}"
				obligations_for_node="$(awk -F '\t' -v wanted="$node_id" '
					NR > 1 {
						n=split($2, ids, ",")
						for (i=1; i<=n; i++) if (ids[i] == wanted) {count++; break}
					}
					END {print count+0}
				' "$coverage_source")"
				(( obligations_for_node <= HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF )) ||
					die "Luna node $node_id inherits $obligations_for_node obligations; maximum is $HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF, so split its semantic responsibility"
			done < <(tail -n +2 "$dag_tmp")
		fi
		install -m 600 "$coverage_source" "$coverage_tmp"
	elif [[ -n "$coverage_source" ]]; then
		die 'coverage file supplied without normalized Specification IR'
	fi
	if (( has_complexity == 1 )); then
		write_decomposition_complexity_report "$dag_tmp" "$coverage_source" "$complexity_tmp" ||
			die "decomposition complexity contract rejected one or more nodes; inspect $complexity_tmp"
	elif (( HARNESS_DECOMPOSITION_CRITIC_ENABLED == 1 )); then
		die "fresh critic-checked decomposition requires the measured DAG schema: $complexity_header"
	fi
	# Delay automatic registry creation until all DAG rows, routing rules, and
	# specification coverage have passed validation, so a rejected plan cannot
	# leave durable sidecar state.
	if (( HARNESS_ARCHITECTURE_GUARDS == 1 )) && ! architecture_registered; then
		architecture_initialize_minimal_test_profile "$dag_tmp" || true
	fi
	architecture_require_registered
	architecture_validate_forced_redesign_plan "$dag_tmp" "${coverage_source:-$coverage_tmp}"
	chmod 600 "$definition_tmp" "$state_tmp" "$dag_tmp"
	mv "$definition_tmp" "$definition"
	mv "$state_tmp" "$state"
	mv "$dag_tmp" "$dag"
	[[ ! -f "$coverage_tmp" ]] || mv "$coverage_tmp" "$coverage"
	[[ ! -f "$complexity_tmp" ]] || mv "$complexity_tmp" "$complexity_report"
	if ! ( architecture_validate_against_plan ); then
		rm -f -- "$definition" "$state" "$dag" "$coverage" "$complexity_report"
		die 'decomposition DAG conflicts with architecture registries; incomplete plan registration was rolled back'
	fi
	provenance="$(decomposition_provenance_file)"
	provenance_tmp="$provenance.tmp.$$"
	{
		printf 'resource_contract_version=%s\n' "$((has_complexity + 1))"
		printf 'planner_model=%s\n' "$DECOMPOSITION_MODEL"
		printf 'planner_reasoning_effort=%s\n' "$DECOMPOSITION_REASONING_EFFORT"
		printf 'max_luna_obligations_per_leaf=%s\n' "$HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF"
		printf 'max_luna_context_capsule_bytes=%s\n' "$HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES"
		printf 'max_luna_complexity_score=%s\n' "$HARNESS_MAX_LUNA_COMPLEXITY_SCORE"
		printf 'max_luna_predicted_p95_tokens=%s\n' "$HARNESS_MAX_LUNA_PREDICTED_P95_TOKENS"
		printf 'created_at=%s\n' "$(timestamp_utc)"
	} > "$provenance_tmp"
	chmod 600 "$provenance_tmp"
	mv "$provenance_tmp" "$provenance"
	log_event "PROJECT_DECOMPOSITION_V2_INITIALIZED nodes=$(project_plan_total_count) file=$dag coverage=$([[ -f "$coverage" ]] && printf '%s' "$coverage" || printf disabled)"
	trace_event PROJECT_DECOMPOSITION_V2_INITIALIZED "nodes=$(project_plan_total_count)" "dag_file=$dag"
}

activate_project_plan_item()
{
	local item_id="$1"
	local root="$2"
	local state status existing_root tmp
	state="$(project_plan_state_file)"
	project_plan_exists || die 'project plan is missing; initialize it before publishing tasks'
	status="$(project_plan_item_status "$item_id")"
	[[ -n "$status" ]] || die "unknown project plan item: $item_id"
	existing_root="$(project_plan_item_root "$item_id")"
	if [[ "$status" == ACTIVE && "$existing_root" == "$root" ]]; then
		return 0
	fi
	[[ "$status" == PENDING ]] || die "project plan item is not pending: $item_id ($status)"
	project_plan_dependencies_satisfied "$item_id" || die "project plan dependencies are not complete for item: $item_id"
	[[ -z "$(project_plan_item_for_root "$root")" ]] || die "task root is already assigned to a project plan item: $root"
	[[ -z "$(awk -F '\t' '!/^#/ && $2 == "ACTIVE" {print $1; exit}' "$state")" ]] || die 'another project plan item is already active'
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v root="$root" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "ACTIVE"; $3 = root; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
	log_event "PROJECT_PLAN_ITEM_ACTIVATED item=$item_id root=$root"
}

complete_project_plan_item_for_task()
{
	local task_id="$1"
	local root item_id state status tmp
	root="$(task_root_id "$task_id")"
	item_id="$(project_plan_item_for_root "$root")"
	[[ -n "$item_id" ]] || die "task root is not assigned to the project plan: $root"
	status="$(project_plan_item_status "$item_id")"
	[[ "$status" == ACTIVE || "$status" == COMPLETE ]] || die "project plan item cannot be completed from state $status: $item_id"
	[[ "$status" != COMPLETE ]] || return 0
	state="$(project_plan_state_file)"
	tmp="$state.tmp.$$"
	awk -F '\t' -v OFS='\t' -v item="$item_id" -v now="$(timestamp_utc)" '
		/^#/ {print; next}
		$1 == item {$2 = "COMPLETE"; $4 = now}
		{print}
	' "$state" > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$state"
	log_event "PROJECT_PLAN_ITEM_COMPLETED item=$item_id root=$root task=$task_id progress=$(project_plan_progress_percent)"
}

project_completion_recorded()
{
	[[ -f "$(project_complete_file)" ]]
}

mark_project_complete()
{
	local task_id="$1"
	local note_file="${2:-}"
	local file tmp
	project_plan_exists || die 'refusing project completion without a persistent project plan'
	project_plan_all_complete || die "refusing project completion with $(project_plan_pending_count) unfinished project plan item(s)"
	specification_coverage_completion_ready || die 'refusing project completion with incomplete normalized specification coverage'
	architecture_require_completion_ready
	file="$(project_complete_file)"
	tmp="$file.tmp.$$"
	{
		printf 'project=%s\n' "$PROJECT"
		printf 'task_id=%s\n' "$task_id"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'completed_at=%s\n' "$(timestamp_utc)"
		if [[ -n "$note_file" ]]; then
			printf 'note_file=%s\n' "$note_file"
		fi
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$file"
	log_event "PROJECT_COMPLETED task=$task_id file=$file"
	trace_event PROJECT_COMPLETED "task_id=$task_id" "completion_file=$file" "note_file=${note_file:-}"
}

list_descendants_of_pid()
{
	local root_pid="$1"
	ps -eo pid=,ppid= | awk -v root="$root_pid" '
		{ children[$2] = children[$2] " " $1 }
		function walk(pid,    n, ids, i) {
			n = split(children[pid], ids, /[[:space:]]+/)
			for (i = 1; i <= n; i++) {
				if (ids[i] != "") {
					print ids[i]
					walk(ids[i])
				}
			}
		}
		END { walk(root) }
	'
}

terminate_descendants_of_pid()
{
	local root_pid="$1"
	local descendants
	descendants="$(list_descendants_of_pid "$root_pid" | tr '\n' ' ' | xargs -r printf '%s ')"
	[[ -n "$descendants" ]] || return 0
	kill $descendants 2>/dev/null || true
	sleep 0.2
	kill -9 $descendants 2>/dev/null || true
}

write_irregularity_snapshot_fields()
{
	printf 'irregularity_detection_enabled=%s\n' "$HARNESS_IRREGULARITY_DETECTION_ENABLED"
	printf 'relative_token_regression_percent=%s\n' "$HARNESS_RELATIVE_TOKEN_REGRESSION_PERCENT"
	printf 'relative_token_history_min_samples=%s\n' "$HARNESS_RELATIVE_TOKEN_HISTORY_MIN_SAMPLES"
	printf 'efficiency_warning_repeat_limit=%s\n' "$HARNESS_EFFICIENCY_WARNING_REPEAT_LIMIT"
	printf 'max_episodes_without_verified_facet=%s\n' "$HARNESS_MAX_EPISODES_WITHOUT_VERIFIED_FACET"
	printf 'max_tokens_without_verified_facet=%s\n' "$HARNESS_MAX_TOKENS_WITHOUT_VERIFIED_FACET"
	printf 'token_accounting_mismatch_percent=%s\n' "$HARNESS_TOKEN_ACCOUNTING_MISMATCH_PERCENT"
	printf 'token_accounting_mismatch_min_tokens=%s\n' "$HARNESS_TOKEN_ACCOUNTING_MISMATCH_MIN_TOKENS"
	printf 'max_state_oscillations=%s\n' "$HARNESS_MAX_STATE_OSCILLATIONS"
	printf 'max_patch_churn_rounds=%s\n' "$HARNESS_MAX_PATCH_CHURN_ROUNDS"
}

write_project_snapshot()
{
	local config tmp
	config="$(project_dir)/project.conf"
	tmp="$config.tmp.$$"
	{
		printf 'project=%s\n' "$PROJECT"
		printf 'repository=%s\n' "$REPOSITORY"
		printf 'harness_mode=%s\n' "$HARNESS_MODE"
		printf 'decomposition_v2=%s\n' "$HARNESS_DECOMPOSITION_V2"
		printf 'specification_review_enabled=%s\n' "$HARNESS_SPECIFICATION_REVIEW_ENABLED"
		printf 'domain_profiles=%s\n' "${HARNESS_DOMAIN_PROFILES:-}"
		printf 'domain_profiles_sha256=%s\n' "$(domain_profiles_sha256)"
		printf 'architecture_guards=%s\n' "$HARNESS_ARCHITECTURE_GUARDS"
		printf 'repository_index_mode=%s\n' "$HARNESS_REPOSITORY_INDEX_MODE"
		printf 'context_closure_mode=%s\n' "$HARNESS_CONTEXT_CLOSURE_MODE"
		printf 'patch_only_max_validation_rounds=%s\n' "$HARNESS_PATCH_ONLY_MAX_VALIDATION_ROUNDS"
		printf 'repository_index_root=%s\n' "$HARNESS_REPOSITORY_INDEX_ROOT"
		printf 'compile_commands=%s\n' "$HARNESS_COMPILE_COMMANDS"
		printf 'semantic_continuation_review_enabled=%s\n' "$HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED"
		write_irregularity_snapshot_fields
		printf 'harness_home=%s\n' "$HARNESS_HOME"
		printf 'harness_bin=%s\n' "$HARNESS_BIN"
		printf 'project_tmp_dir=%s\n' "$(project_tmp_dir)"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_manager_snapshot()
{
	local config tmp
	config="$(project_dir)/control/manager.conf"
	tmp="$config.tmp.$$"
	{
		printf 'specification=%s\n' "$SPECIFICATION"
		printf 'model=%s\n' "$MANAGER_MODEL"
		printf 'reasoning_effort=%s\n' "$MANAGER_REASONING_EFFORT"
		printf 'decomposition_model=%s\n' "$DECOMPOSITION_MODEL"
		printf 'decomposition_reasoning_effort=%s\n' "$DECOMPOSITION_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$MANAGER_SANDBOX"
		printf 'codex_bin=%s\n' "$MANAGER_CODEX_BIN"
		printf 'codex_home=%s\n' "$MANAGER_CODEX_HOME"
		printf 'runtime_path_prefix=%s\n' "$HARNESS_RUNTIME_PATH_PREFIX"
		printf 'auto_replan_enabled=%s\n' "$HARNESS_AUTO_REPLAN_ENABLED"
		printf 'max_auto_replans_without_verified_gain=%s\n' "$HARNESS_MAX_AUTO_REPLANS_WITHOUT_VERIFIED_GAIN"
		printf 'max_total_root_reviews=%s\n' "$HARNESS_MAX_TOTAL_ROOT_REVIEWS"
		printf 'max_total_root_replans=%s\n' "$HARNESS_MAX_TOTAL_ROOT_REPLANS"
		printf 'max_root_reviews_without_criterion=%s\n' "$HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION"
		printf 'max_agent_items_per_invocation=%s\n' "$HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION"
		printf 'agent_item_headroom=%s\n' "$HARNESS_AGENT_ITEM_HEADROOM"
		printf 'max_manager_review_items_per_invocation=%s\n' "$HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION"
		printf 'max_manager_replan_items_per_invocation=%s\n' "$HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION"
		printf 'max_manager_replan_publish_attempts=%s\n' "$HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS"
		printf 'max_identical_manager_remediation_blockers=%s\n' "$HARNESS_MAX_IDENTICAL_MANAGER_REMEDIATION_BLOCKERS"
		printf 'max_agent_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_agent_estimated_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_worker_task_processed_tokens=%s\n' "$HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS"
		printf 'max_specification_review_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_decomposition_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_root_child_criteria=%s\n' "$HARNESS_MAX_ROOT_CHILD_CRITERIA"
		printf 'max_criterion_depth=%s\n' "$HARNESS_MAX_CRITERION_DEPTH"
		printf 'max_root_lifetime_seconds=%s\n' "$HARNESS_MAX_ROOT_LIFETIME_SECONDS"
		printf 'max_root_processed_tokens=%s\n' "$HARNESS_MAX_ROOT_PROCESSED_TOKENS"
		write_irregularity_snapshot_fields
		printf 'preferred_worker_route=%s\n' "$HARNESS_PREFERRED_WORKER_ROUTE"
		printf 'agent_commits_enabled=%s\n' "$HARNESS_AGENT_COMMITS_ENABLED"
		printf 'min_luna_node_percent=%s\n' "$HARNESS_MIN_LUNA_NODE_PERCENT"
		printf 'min_luna_coding_node_percent=%s\n' "$HARNESS_MIN_LUNA_CODING_NODE_PERCENT"
		printf 'architecture_guards=%s\n' "$HARNESS_ARCHITECTURE_GUARDS"
		printf 'semantic_continuation_review_enabled=%s\n' "$HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED"
		printf 'domain_profiles=%s\n' "${HARNESS_DOMAIN_PROFILES:-}"
		printf 'domain_profiles_sha256=%s\n' "$(domain_profiles_sha256)"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_worker_snapshot()
{
	local config tmp
	config="$(project_dir)/control/worker.conf"
	tmp="$config.tmp.$$"
	{
		printf 'model=%s\n' "$WORKER_MODEL"
		printf 'reasoning_effort=%s\n' "$WORKER_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$WORKER_SANDBOX"
		printf 'codex_bin=%s\n' "$WORKER_CODEX_BIN"
		printf 'codex_home=%s\n' "$WORKER_CODEX_HOME"
		printf 'runtime_path_prefix=%s\n' "$HARNESS_RUNTIME_PATH_PREFIX"
		printf 'heartbeat_seconds=%s\n' "$WORKER_HEARTBEAT_SECONDS"
		printf 'reuse_root_threads=%s\n' "$HARNESS_REUSE_WORKER_THREADS"
		printf 'thread_max_rejections=%s\n' "$HARNESS_WORKER_THREAD_MAX_REJECTIONS"
		printf 'max_root_attempts=%s\n' "$HARNESS_MAX_ROOT_ATTEMPTS"
		printf 'max_zero_gain_window=%s\n' "$HARNESS_MAX_ZERO_GAIN_WINDOW"
		printf 'max_checkpoints_without_criterion=%s\n' "$HARNESS_MAX_CHECKPOINTS_WITHOUT_CRITERION"
		printf 'max_total_root_reviews=%s\n' "$HARNESS_MAX_TOTAL_ROOT_REVIEWS"
		printf 'max_total_root_replans=%s\n' "$HARNESS_MAX_TOTAL_ROOT_REPLANS"
		printf 'max_root_reviews_without_criterion=%s\n' "$HARNESS_MAX_ROOT_REVIEWS_WITHOUT_CRITERION"
		printf 'max_agent_items_per_invocation=%s\n' "$HARNESS_MAX_AGENT_ITEMS_PER_INVOCATION"
		printf 'agent_item_headroom=%s\n' "$HARNESS_AGENT_ITEM_HEADROOM"
		printf 'max_manager_review_items_per_invocation=%s\n' "$HARNESS_MAX_MANAGER_REVIEW_ITEMS_PER_INVOCATION"
		printf 'max_manager_replan_items_per_invocation=%s\n' "$HARNESS_MAX_MANAGER_REPLAN_ITEMS_PER_INVOCATION"
		printf 'max_manager_replan_publish_attempts=%s\n' "$HARNESS_MAX_MANAGER_REPLAN_PUBLISH_ATTEMPTS"
		printf 'max_agent_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_AGENT_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_agent_estimated_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_AGENT_ESTIMATED_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_worker_task_processed_tokens=%s\n' "$HARNESS_MAX_WORKER_TASK_PROCESSED_TOKENS"
		printf 'max_specification_review_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_SPECIFICATION_REVIEW_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_decomposition_processed_tokens_per_invocation=%s\n' "$HARNESS_MAX_DECOMPOSITION_PROCESSED_TOKENS_PER_INVOCATION"
		printf 'max_root_child_criteria=%s\n' "$HARNESS_MAX_ROOT_CHILD_CRITERIA"
		printf 'max_criterion_depth=%s\n' "$HARNESS_MAX_CRITERION_DEPTH"
		printf 'max_root_lifetime_seconds=%s\n' "$HARNESS_MAX_ROOT_LIFETIME_SECONDS"
		printf 'max_root_processed_tokens=%s\n' "$HARNESS_MAX_ROOT_PROCESSED_TOKENS"
		write_irregularity_snapshot_fields
		printf 'closure_mode_enabled=%s\n' "$HARNESS_CLOSURE_MODE_ENABLED"
		printf 'closure_min_progress=%s\n' "$HARNESS_CLOSURE_MODE_MIN_PROGRESS"
		printf 'closure_max_fixes=%s\n' "$HARNESS_CLOSURE_MODE_MAX_FIXES"
		printf 'closure_max_smoke_runs=%s\n' "$HARNESS_CLOSURE_MODE_MAX_SMOKE_RUNS"
		printf 'goal_mode=%s\n' "$HARNESS_WORKER_GOAL_MODE"
		printf 'goal_max_identical_iterations=%s\n' "$HARNESS_GOAL_MAX_IDENTICAL_ITERATIONS"
		printf 'goal_context_rotation_iterations=%s\n' "$HARNESS_GOAL_CONTEXT_ROTATION_ITERATIONS"
		printf 'goal_process_max_fixes=%s\n' "$HARNESS_GOAL_PROCESS_MAX_FIXES"
		printf 'goal_process_max_smoke_runs=%s\n' "$HARNESS_GOAL_PROCESS_MAX_SMOKE_RUNS"
		printf 'semantic_continuation_review_enabled=%s\n' "$HARNESS_SEMANTIC_CONTINUATION_REVIEW_ENABLED"
		printf 'decomposition_v2=%s\n' "$HARNESS_DECOMPOSITION_V2"
		printf 'decomposition_critic_enabled=%s\n' "$HARNESS_DECOMPOSITION_CRITIC_ENABLED"
		printf 'specification_review_enabled=%s\n' "$HARNESS_SPECIFICATION_REVIEW_ENABLED"
		printf 'domain_profiles=%s\n' "${HARNESS_DOMAIN_PROFILES:-}"
		printf 'domain_profiles_sha256=%s\n' "$(domain_profiles_sha256)"
		printf 'max_luna_strategy_failures=%s\n' "$HARNESS_MAX_LUNA_STRATEGY_FAILURES"
		printf 'max_luna_allowed_paths=%s\n' "$HARNESS_MAX_LUNA_ALLOWED_PATHS"
		printf 'max_luna_obligations_per_leaf=%s\n' "$HARNESS_MAX_LUNA_OBLIGATIONS_PER_LEAF"
		printf 'max_luna_context_capsule_bytes=%s\n' "$HARNESS_MAX_LUNA_CONTEXT_CAPSULE_BYTES"
		printf 'validation_output_max_lines=%s\n' "$HARNESS_VALIDATION_OUTPUT_MAX_LINES"
		printf 'validation_output_max_bytes=%s\n' "$HARNESS_VALIDATION_OUTPUT_MAX_BYTES"
		printf 'min_luna_node_percent=%s\n' "$HARNESS_MIN_LUNA_NODE_PERCENT"
		printf 'min_luna_coding_node_percent=%s\n' "$HARNESS_MIN_LUNA_CODING_NODE_PERCENT"
		printf 'architecture_guards=%s\n' "$HARNESS_ARCHITECTURE_GUARDS"
		printf 'preferred_worker_route=%s\n' "$HARNESS_PREFERRED_WORKER_ROUTE"
		printf 'agent_commits_enabled=%s\n' "$HARNESS_AGENT_COMMITS_ENABLED"
		printf 'luna_model=%s\n' "$LUNA_WORKER_MODEL"
		printf 'luna_reasoning_effort=%s\n' "$LUNA_WORKER_REASONING_EFFORT"
		printf 'terra_model=%s\n' "$TERRA_WORKER_MODEL"
		printf 'terra_reasoning_effort=%s\n' "$TERRA_WORKER_REASONING_EFFORT"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}

write_oracle_snapshot()
{
	local config tmp
	config="$(project_dir)/control/oracle.conf"
	tmp="$config.tmp.$$"
	{
		printf 'enabled=%s\n' "$ORACLE_ENABLED"
		printf 'max_runs=%s\n' "${MAX_ORACLE_RUNS:-(unlimited)}"
		printf 'model=%s\n' "$ORACLE_MODEL"
		printf 'fallback_model=%s\n' "$ORACLE_FALLBACK_MODEL"
		printf 'reasoning_effort=%s\n' "$ORACLE_REASONING_EFFORT"
		printf 'sandbox=%s\n' "$ORACLE_SANDBOX"
		printf 'codex_bin=%s\n' "$ORACLE_CODEX_BIN"
		printf 'codex_home=%s\n' "$ORACLE_CODEX_HOME"
		printf 'runtime_path_prefix=%s\n' "$HARNESS_RUNTIME_PATH_PREFIX"
		printf 'env_file=%s\n' "$HARNESS_ENV_FILE"
		printf 'env_sha256=%s\n' "$(env_sha256)"
		printf 'updated_at=%s\n' "$(timestamp_utc)"
	} > "$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$config"
}
