#!/usr/bin/env bash
# Score a light-harness run and compare it with the archived full baseline.
set -Eeuo pipefail

[[ $# -eq 1 ]] ||
	{ printf 'Usage: %s RUN_DIRECTORY\n' "${0##*/}" >&2; exit 2; }
run_dir="$(cd "$1" && pwd)"
grader="$run_dir/grader.sh"
repo="$run_dir/repository"
full_ref="$(head -n 1 "$run_dir/full-baseline.path")"
if [[ "$full_ref" = /* ]]; then
	full_run="$full_ref"
else
	full_run="$(cd "$run_dir" && cd "$full_ref" && pwd)"
fi
if [[ ! -f "$full_run/comparison.tsv" ]]; then
	light_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	full_run="$light_dir/../full_harness/runs/pbnfc-html8-terra-vs-harness-20260727a"
fi
full_tsv="$full_run/comparison.tsv"
[[ -x "$grader" && -d "$repo" && -f "$full_tsv" ]] ||
	{ printf 'run or full baseline is incomplete\n' >&2; exit 2; }

metric_value()
{
	local file="$1" key="$2"
	[[ -f "$file" ]] || { printf 'n/a'; return; }
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

pricing_value()
{
	local key="$1"
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$run_dir/pricing.env"
}

sum_json_usage()
{
	local root="$1" pattern="$2" field="$3"
	while IFS= read -r -d '' file; do
		jq -rs --arg field "$field" --arg fallback "$file" '
			([.[] | select(.type == "thread.started") | .thread_id] |
				first // $fallback) as $thread
			| ([.[] | select(.type == "turn.completed") |
				(.usage[$field] // 0)] | max // 0) as $value
			| [$thread, $value] | @tsv
		' "$file" 2>/dev/null
	done < <(find "$root" -name "$pattern" -type f -print0 2>/dev/null) |
		awk -F '\t' '
			NF >= 2 && $2 > maximum[$1] { maximum[$1] = $2 }
			END {
				for (thread in maximum) total += maximum[thread]
				print total + 0
			}'
}

count_turns()
{
	local root="$1" pattern="$2"
	find "$root" -name "$pattern" -type f -print0 2>/dev/null |
		xargs -0 -r jq -s '
			[.[] | select(.type == "turn.completed")] | length
		' 2>/dev/null |
		awk '{ total += $1 } END { print total + 0 }'
}

count_source_lines()
{
	find "$repo/src" "$repo/include" -type f \
		\( -name '*.c' -o -name '*.h' \) -print0 2>/dev/null |
		xargs -0 -r wc -l 2>/dev/null |
		awk 'END { print $1 + 0 }'
}

estimated_usd()
{
	local input="$1" cached="$2" output="$3"
	local input_rate="$4" cached_rate="$5" output_rate="$6"
	awk -v input="$input" -v cached="$cached" -v output="$output" \
		-v input_rate="$input_rate" -v cached_rate="$cached_rate" \
		-v output_rate="$output_rate" '
		BEGIN {
			uncached = input - cached;
			if (uncached < 0) uncached = 0;
			cost = uncached * input_rate + cached * cached_rate;
			cost += output * output_rate;
			printf "%.6f", cost / 1000000;
		}'
}

full_field()
{
	local column="$1"
	awk -F '\t' -v column="$column" '
		NR == 1 {
			for (i = 1; i <= NF; ++i)
				if ($i == column) wanted = i
			next
		}
		$1 == "manager-terra-high_worker-luna-high" {
			print $wanted
			exit
		}
	' "$full_tsv"
}

set +e
"$grader" "$repo" > "$run_dir/grader.out" 2>&1
grader_exit=$?
set -e
grader_score="$(awk '/^SCORE / { print $2; found=1 }
	END { if (!found) print "0/12" }' "$run_dir/grader.out")"

project_logs="$(find "$run_dir/state/projects" -mindepth 2 -maxdepth 2 \
	-type d -name logs -print -quit)"
terra_input="$(sum_json_usage "$project_logs" 'manager-*.jsonl' input_tokens)"
terra_cached="$(sum_json_usage "$project_logs" 'manager-*.jsonl' cached_input_tokens)"
terra_output="$(sum_json_usage "$project_logs" 'manager-*.jsonl' output_tokens)"
luna_input="$(sum_json_usage "$project_logs" 'worker-*.jsonl' input_tokens)"
luna_cached="$(sum_json_usage "$project_logs" 'worker-*.jsonl' cached_input_tokens)"
luna_output="$(sum_json_usage "$project_logs" 'worker-*.jsonl' output_tokens)"
total_input="$((terra_input + luna_input))"
total_cached="$((terra_cached + luna_cached))"
total_output="$((terra_output + luna_output))"
terra_turns="$(count_turns "$project_logs" 'manager-*.jsonl')"
luna_turns="$(count_turns "$project_logs" 'worker-*.jsonl')"
total_turns="$((terra_turns + luna_turns))"
handoffs=$((total_turns > 0 ? total_turns - 1 : 0))
cycles="$(find "$project_logs" -name 'worker-*.jsonl' -type f | wc -l | tr -d ' ')"
seconds="$(metric_value "$run_dir/timing.env" seconds)"
source_lines="$(count_source_lines)"
source_files="$(find "$repo/src" "$repo/include" -type f \
	\( -name '*.c' -o -name '*.h' \) 2>/dev/null | wc -l | tr -d ' ')"
test_files="$(find "$repo/tests" -type f 2>/dev/null | wc -l | tr -d ' ')"
test_lines="$(find "$repo/tests" -type f -print0 2>/dev/null |
	xargs -0 -r wc -l 2>/dev/null | awk 'END { print $1 + 0 }')"
readme_lines="$(wc -l < "$repo/README.md")"

terra_cost="$(estimated_usd "$terra_input" "$terra_cached" "$terra_output" \
	"$(pricing_value BENCHMARK_TERRA_INPUT_USD_PER_M)" \
	"$(pricing_value BENCHMARK_TERRA_CACHED_INPUT_USD_PER_M)" \
	"$(pricing_value BENCHMARK_TERRA_OUTPUT_USD_PER_M)")"
luna_cost="$(estimated_usd "$luna_input" "$luna_cached" "$luna_output" \
	"$(pricing_value BENCHMARK_LUNA_INPUT_USD_PER_M)" \
	"$(pricing_value BENCHMARK_LUNA_CACHED_INPUT_USD_PER_M)" \
	"$(pricing_value BENCHMARK_LUNA_OUTPUT_USD_PER_M)")"
total_cost="$(awk -v terra="$terra_cost" -v luna="$luna_cost" \
	'BEGIN { printf "%.6f", terra + luna }')"

full_score="$(full_field grader_score)"
full_seconds="$(full_field seconds)"
full_turns="$(full_field completed_turns)"
full_handoffs="$(full_field manager_worker_switches)"
full_input="$(full_field input_tokens)"
full_cached="$(full_field cached_input_tokens)"
full_output="$(full_field output_tokens)"
full_cost="$(full_field estimated_api_usd)"
full_lines="$(full_field c_header_lines)"

ratio()
{
	awk -v numerator="$1" -v denominator="$2" \
		'BEGIN {
			if (denominator == 0) print "n/a";
			else printf "%.4f", numerator / denominator
		}'
}

saving_percent="$(awk -v light="$total_cost" -v full="$full_cost" \
	'BEGIN { printf "%.2f", (1 - light / full) * 100 }')"

cat > "$run_dir/comparison.tsv" <<EOF
competitor	grader_score	grader_exit	seconds	completed_turns	manager_worker_handoffs	input_tokens	cached_input_tokens	output_tokens	estimated_api_usd	c_header_lines
full-harness-terra-high_luna-high	$full_score	0	$full_seconds	$full_turns	$full_handoffs	$full_input	$full_cached	$full_output	$full_cost	$full_lines
light-harness-terra-high_luna-high	$grader_score	$grader_exit	$seconds	$total_turns	$handoffs	$total_input	$total_cached	$total_output	$total_cost	$source_lines
EOF

cat > "$run_dir/role-usage.tsv" <<EOF
role	completed_turns	input_tokens	cached_input_tokens	uncached_input_tokens	output_tokens	estimated_api_usd
terra-manager	$terra_turns	$terra_input	$terra_cached	$((terra_input - terra_cached))	$terra_output	$terra_cost
luna-worker	$luna_turns	$luna_input	$luna_cached	$((luna_input - luna_cached))	$luna_output	$luna_cost
combined	$total_turns	$total_input	$total_cached	$((total_input - total_cached))	$total_output	$total_cost
EOF

cat > "$run_dir/quality-summary.tsv" <<EOF
metric	full-harness	light-harness
external_grader_score	$full_score	$grader_score
c_header_files	15	$source_files
c_header_physical_lines	$full_lines	$source_lines
project_test_files	12	$test_files
project_test_physical_lines	1999	$test_lines
readme_physical_lines	159	$readme_lines
EOF

cat > "$run_dir/comparison.md" <<EOF
# Full harness versus light harness

The light run used the byte-identical archived \`pbnfc\` specification and the
same deterministic external grader as the full-harness baseline.

| Metric | Full harness | Light harness | Light/full |
|---|---:|---:|---:|
| Functional score | $full_score | $grader_score | — |
| Wall seconds | $full_seconds | $seconds | $(ratio "$seconds" "$full_seconds")x |
| Completed model turns | $full_turns | $total_turns | $(ratio "$total_turns" "$full_turns")x |
| Manager/worker handoffs | $full_handoffs | $handoffs | $(ratio "$handoffs" "$full_handoffs")x |
| Input tokens including cache | $full_input | $total_input | $(ratio "$total_input" "$full_input")x |
| Cached-input reads | $full_cached | $total_cached | $(ratio "$total_cached" "$full_cached")x |
| Uncached input | $((full_input - full_cached)) | $((total_input - total_cached)) | $(ratio "$((total_input - total_cached))" "$((full_input - full_cached))")x |
| Output tokens | $full_output | $total_output | $(ratio "$total_output" "$full_output")x |
| API-price-equivalent USD | $full_cost | $total_cost | $(ratio "$total_cost" "$full_cost")x |
| C/header physical lines | $full_lines | $source_lines | $(ratio "$source_lines" "$full_lines")x |

At the supplied rates, the light run used **$saving_percent% less
API-price-equivalent cost** than the full harness.

## Light role breakdown

| Role | Turns | Input / cached / uncached | Output | Cost equivalent |
|---|---:|---:|---:|---:|
| Terra manager | $terra_turns | $terra_input / $terra_cached / $((terra_input - terra_cached)) | $terra_output | \$$terra_cost |
| Luna worker | $luna_turns | $luna_input / $luna_cached / $((luna_input - luna_cached)) | $luna_output | \$$luna_cost |
| Combined | $total_turns | $total_input / $total_cached / $((total_input - total_cached)) | $total_output | **\$$total_cost** |

The light harness completed $cycles Luna implementation/remediation cycle(s).
Provider usage is deduplicated by Codex thread ID: resumed cumulative Luna
snapshots are not added repeatedly.

## Artifact-size indicators

| Measure | Full harness | Light harness |
|---|---:|---:|
| C/header files | 15 | $source_files |
| C/header physical lines | $full_lines | $source_lines |
| Project test files | 12 | $test_files |
| Project test physical lines | 1999 | $test_lines |
| README physical lines | 159 | $readme_lines |

Functional grader output is in [grader.out](grader.out), exact per-role usage in
[role-usage.tsv](role-usage.tsv), and machine-readable comparison data in
[comparison.tsv](comparison.tsv).

The dollar values are API-price equivalents based on the supplied token rates.
Because this run uses ChatGPT authentication, they are not an itemized invoice.
This is one fresh light run compared with one earlier full run, so model
stochasticity and run-time conditions remain experimental limitations.
EOF

printf 'Wrote %s\n' "$run_dir/comparison.md"
[[ "$grader_exit" == 0 ]]
