#!/usr/bin/env bash
# Score a completed or interrupted benchmark run without invoking any model.
set -Eeuo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: %s RUN_DIRECTORY\n' "${0##*/}" >&2; exit 2; }
run_dir="$(cd "$1" && pwd)"
grader="$run_dir/grader.sh"
[[ -x "$grader" ]] || { printf 'grader is missing: %s\n' "$grader" >&2; exit 2; }

metric_value()
{
	local file="$1" key="$2"
	[[ -f "$file" ]] || { printf 'n/a'; return; }
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

pricing_value()
{
	local key="$1" file="$run_dir/pricing.env"
	[[ -f "$file" ]] || { printf ''; return; }
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

sum_json_usage()
{
	local root="$1" pattern="$2" field="$3"
	if ! command -v jq >/dev/null 2>&1; then printf 'n/a'; return; fi
	while IFS= read -r -d '' file; do
		jq -rs --arg field "$field" --arg fallback "$file" '
			([.[] | select(.type == "thread.started") | .thread_id] | first // $fallback) as $thread
			| ([.[] | select(.type == "turn.completed") | (.usage[$field] // 0)] | max // 0) as $value
			| [$thread, $value]
			| @tsv
		' "$file" 2>/dev/null
	done < <(find "$root" -name "$pattern" -type f -print0 2>/dev/null) |
		awk -F '\t' '
			NF >= 2 && $2 > maximum[$1] { maximum[$1] = $2 }
			END {
				for (thread in maximum) total += maximum[thread]
				print total + 0
			}'
}

estimated_usd()
{
	local input="$1" cached="$2" output="$3" input_rate="$4" cached_rate="$5" output_rate="$6"
	[[ "$input" =~ ^[0-9]+$ && "$cached" =~ ^[0-9]+$ && "$output" =~ ^[0-9]+$ ]] || { printf 'n/a'; return; }
	[[ "$input_rate" =~ ^[0-9]+([.][0-9]+)?$ && "$cached_rate" =~ ^[0-9]+([.][0-9]+)?$ && "$output_rate" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf 'n/a'; return; }
	awk -v input="$input" -v cached="$cached" -v output="$output" \
		-v input_rate="$input_rate" -v cached_rate="$cached_rate" -v output_rate="$output_rate" '
		BEGIN {
			non_cached = input - cached;
			if (non_cached < 0) non_cached = 0;
			printf "%.6f", (non_cached * input_rate + cached * cached_rate + output * output_rate) / 1000000;
		}'
}

sum_usd()
{
	local left="$1" right="$2"
	[[ "$left" != n/a && "$right" != n/a ]] || { printf 'n/a'; return; }
	awk -v left="$left" -v right="$right" 'BEGIN { printf "%.6f", left + right }'
}

count_turns()
{
	local root="$1"
	find "$root" -name '*.jsonl' -type f -print0 2>/dev/null |
		xargs -0 -r grep -h '"type":"turn.completed"' 2>/dev/null | wc -l | tr -d ' '
}

count_lines()
{
	local repo="$1"
	find "$repo/src" "$repo/include" -type f \( -name '*.c' -o -name '*.h' \) -print0 2>/dev/null |
		xargs -0 -r wc -l 2>/dev/null | awk 'END { print $1 + 0 }'
}

grade()
{
	local name="$1" repo="$2" output
	output="$run_dir/$name/grader.out"
	set +e
	"$grader" "$repo" > "$output" 2>&1
	local status=$?
	set -e
	awk '/^SCORE / { print $2; found=1 } END { if (!found) print "0/12" }' "$output"
	return "$status"
}

single_repo="$run_dir/single/repository"
pair_repo="$run_dir/manager-worker/repository"
set +e
single_score="$(grade single "$single_repo")"; single_grade_status=$?
pair_score="$(grade manager-worker "$pair_repo")"; pair_grade_status=$?
set -e

single_seconds="$(metric_value "$run_dir/single/timing.env" seconds)"
pair_seconds="$(metric_value "$run_dir/manager-worker/timing.env" seconds)"
single_input="$(sum_json_usage "$run_dir/single" events.jsonl input_tokens)"
single_cached_input="$(sum_json_usage "$run_dir/single" events.jsonl cached_input_tokens)"
single_output="$(sum_json_usage "$run_dir/single" events.jsonl output_tokens)"
pair_terra_input="$(sum_json_usage "$run_dir/manager-worker/state" 'manager-*.jsonl' input_tokens)"
pair_terra_cached_input="$(sum_json_usage "$run_dir/manager-worker/state" 'manager-*.jsonl' cached_input_tokens)"
pair_terra_output="$(sum_json_usage "$run_dir/manager-worker/state" 'manager-*.jsonl' output_tokens)"
pair_luna_input="$(sum_json_usage "$run_dir/manager-worker/state" 'worker-*.jsonl' input_tokens)"
pair_luna_cached_input="$(sum_json_usage "$run_dir/manager-worker/state" 'worker-*.jsonl' cached_input_tokens)"
pair_luna_output="$(sum_json_usage "$run_dir/manager-worker/state" 'worker-*.jsonl' output_tokens)"
pair_input="$((pair_terra_input + pair_luna_input))"
pair_cached_input="$((pair_terra_cached_input + pair_luna_cached_input))"
pair_output="$((pair_terra_output + pair_luna_output))"
single_turns="$(count_turns "$run_dir/single")"
pair_turns="$(count_turns "$run_dir/manager-worker/state")"
pair_switches="$(grep -c 'WORKER_CONTEXT_SELECTED\|MANAGER_.*STARTED' "$run_dir/manager-worker/state/projects"/*/logs/events.log 2>/dev/null || true)"
single_lines="$(count_lines "$single_repo")"
pair_lines="$(count_lines "$pair_repo")"

terra_input_rate="$(pricing_value BENCHMARK_TERRA_INPUT_USD_PER_M)"
terra_cached_input_rate="$(pricing_value BENCHMARK_TERRA_CACHED_INPUT_USD_PER_M)"
terra_output_rate="$(pricing_value BENCHMARK_TERRA_OUTPUT_USD_PER_M)"
luna_input_rate="$(pricing_value BENCHMARK_LUNA_INPUT_USD_PER_M)"
luna_cached_input_rate="$(pricing_value BENCHMARK_LUNA_CACHED_INPUT_USD_PER_M)"
luna_output_rate="$(pricing_value BENCHMARK_LUNA_OUTPUT_USD_PER_M)"
single_usd="$(estimated_usd "$single_input" "$single_cached_input" "$single_output" "$terra_input_rate" "$terra_cached_input_rate" "$terra_output_rate")"
pair_terra_usd="$(estimated_usd "$pair_terra_input" "$pair_terra_cached_input" "$pair_terra_output" "$terra_input_rate" "$terra_cached_input_rate" "$terra_output_rate")"
pair_luna_usd="$(estimated_usd "$pair_luna_input" "$pair_luna_cached_input" "$pair_luna_output" "$luna_input_rate" "$luna_cached_input_rate" "$luna_output_rate")"
pair_usd="$(sum_usd "$pair_terra_usd" "$pair_luna_usd")"

tsv="$run_dir/comparison.tsv"
printf 'competitor\tgrader_score\tgrader_exit\tseconds\tcompleted_turns\tmanager_worker_switches\tinput_tokens\tcached_input_tokens\toutput_tokens\testimated_api_usd\tc_header_lines\n' > "$tsv"
printf 'single-terra-high\t%s\t%s\t%s\t%s\t0\t%s\t%s\t%s\t%s\t%s\n' "$single_score" "$single_grade_status" "$single_seconds" "$single_turns" "$single_input" "$single_cached_input" "$single_output" "$single_usd" "$single_lines" >> "$tsv"
printf 'manager-terra-high_worker-luna-high\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pair_score" "$pair_grade_status" "$pair_seconds" "$pair_turns" "$pair_switches" "$pair_input" "$pair_cached_input" "$pair_output" "$pair_usd" "$pair_lines" >> "$tsv"

report="$run_dir/comparison.md"
{
	printf '# Benchmark comparison\n\n'
	printf '| Competitor | Functional score | Wall seconds | Completed turns | Manager/worker switches | Input / cached input / output tokens | Estimated API USD | C/header LOC |\n'
	printf '|---|---:|---:|---:|---:|---:|---:|---:|\n'
	printf '| Single Terra High | %s | %s | %s | 0 | %s / %s / %s | %s | %s |\n' "$single_score" "$single_seconds" "$single_turns" "$single_input" "$single_cached_input" "$single_output" "$single_usd" "$single_lines"
	printf '| Manager Terra High + Worker Luna High | %s | %s | %s | %s | %s / %s / %s | %s | %s |\n' "$pair_score" "$pair_seconds" "$pair_turns" "$pair_switches" "$pair_input" "$pair_cached_input" "$pair_output" "$pair_usd" "$pair_lines"
	printf '\nFunctional score is the primary result. Token totals are provider-reported cumulative values, deduplicated by Codex thread; resumed-thread snapshots are not added repeatedly. `n/a` means the JSON events did not contain usage data.\n'
	printf '\nEstimated API USD is calculated from `pricing.env`: uncached input × input rate + cached input × cached-input rate + output × output rate, divided by one million. For a ChatGPT-authenticated run, a populated value is an API-price equivalent based on the supplied rates, not an itemized charge; an empty pricing file produces `n/a`.\n'
	printf '\nDetailed functional logs: [single](single/grader.out) and [manager/worker](manager-worker/grader.out).\n'
} > "$report"
printf 'Wrote %s\n' "$report"
