#!/usr/bin/env bash

# Shared validated commit transaction. The caller must load one mode's common
# library, validate that an implementation worker owns the current turn, and
# set AGENT_COMMIT_SCOPE plus AGENT_COMMIT_ACTOR.

agent_commit_unstage()
{
	(( ${#agent_commit_paths[@]} > 0 )) || return 0
	git -C "$REPOSITORY" reset -q HEAD -- "${agent_commit_paths[@]}" 2>/dev/null || true
}

agent_commit_path_is_generated()
{
	local path="$1" lower base
	lower="${path,,}"
	base="${lower##*/}"
	case "$lower" in
		.git|.git/*|*/.git|*/.git/*|\
		build|build/*|*/build|*/build/*|*/build-*|*/build-*/*|\
		cmake-build-*|cmake-build-*/*|*/cmake-build-*|*/cmake-build-*/*|\
		*/cmakefiles|*/cmakefiles/*|target|target/*|*/target|*/target/*|\
		__pycache__|__pycache__/*|*/__pycache__|*/__pycache__/*)
			return 0
			;;
	esac
	case "$base" in
		*.o|*.obj|*.a|*.so|*.so.*|*.dylib|*.dll|*.exe|*.bin|*.class|*.jar|\
		*.pyc|*.pyo|*.wasm|*.d|*.gcda|*.gcno|*.profraw|*.profdata|\
		*.log|*.core|*.tmp|*.temp|*.swp|*.swo|*.out|\
		cmakecache.txt|cmake_install.cmake|compile_commands.json)
			return 0
			;;
	esac
	return 1
}

agent_commit_path_is_source_related()
{
	local path="$1" lower base
	lower="${path,,}"
	base="${lower##*/}"
	case "$base" in
		makefile|gnumakefile|cmakelists.txt|meson.build|meson_options.txt|\
		dockerfile|containerfile|build|workspace|license|license.*|copying|copying.*|\
		readme|readme.*|changelog|changelog.*|authors|authors.*|notice|notice.*)
			return 0
			;;
	esac
	case "$base" in
		*.c|*.h|*.cc|*.cpp|*.cxx|*.hpp|*.hh|*.hxx|*.hip|*.cu|*.cuh|\
		*.rs|*.go|*.java|*.kt|*.kts|*.py|*.pyi|*.js|*.jsx|*.ts|*.tsx|\
		*.mjs|*.cjs|*.sh|*.bash|*.zsh|*.fish|*.pl|*.pm|*.rb|*.php|\
		*.swift|*.m|*.mm|*.cs|*.scala|*.lua|*.r|*.sql|*.proto|*.f|\
		*.f90|*.f95|*.hs|*.lhs|*.erl|*.ex|*.exs|*.clj|*.cljs|*.fs|\
		*.fsx|*.vb|*.asm|*.s|*.cmake|*.mk|*.in|*.inc|*.def|*.map|*.ld|\
		*.md|*.rst|*.txt|*.adoc|*.json|*.jsonl|*.yaml|*.yml|*.toml|\
		*.ini|*.cfg|*.conf|*.xml|*.csv|*.tsv|*.lock|*.patch|*.diff|\
		*.golden|*.expected|*.fixture|*.snap|*.desktop|*.service|*.example)
			return 0
			;;
	esac
	# Extensionless executable source scripts are allowed only with a shebang.
	if [[ "$base" != *.* && -f "$REPOSITORY/$path" ]]; then
		[[ "$(LC_ALL=C head -c 2 "$REPOSITORY/$path" 2>/dev/null || true)" == '#!' ]]
		return
	fi
	return 1
}

agent_commit_path_in_scope()
{
	local path="$1" scope="$2" entry
	local -a entries=()
	[[ -n "$scope" ]] || return 0
	scope="${scope//;/,}"
	IFS=',' read -r -a entries <<< "$scope"
	for entry in "${entries[@]}"; do
		entry="${entry#"${entry%%[![:space:]]*}"}"
		entry="${entry%"${entry##*[![:space:]]}"}"
		[[ -n "$entry" && "$entry" != NONE && "$entry" != - ]] || continue
		if [[ "$entry" == "$REPOSITORY/"* ]]; then
			entry="${entry#"$REPOSITORY/"}"
		elif [[ "$entry" == /* ]]; then
			continue
		fi
		entry="${entry#./}"
		if [[ "$path" == $entry || "$path" == "${entry%/}"/* ]]; then
			return 0
		fi
	done
	return 1
}

agent_commit_source()
{
	local message_file="$1"
	shift
	local raw path absolute staged_file add_count=0
	local -A requested=()
	local -a agent_commit_paths=()

	(( HARNESS_AGENT_COMMITS_ENABLED == 1 )) || die 'agent source commits are disabled by HARNESS_AGENT_COMMITS_ENABLED=0'
	[[ -f "$message_file" && -s "$message_file" ]] || die 'commit message file is missing or empty'
	(( $# > 0 )) || die 'at least one explicit source or related-artifact path is required'
	git -C "$REPOSITORY" rev-parse --verify HEAD^{commit} >/dev/null 2>&1 || die 'repository has no valid HEAD commit'
	git -C "$REPOSITORY" diff --cached --quiet -- ||
		die 'repository index already contains staged changes; refusing to mix owner or earlier agent state into this commit'
	[[ ! -e "$REPOSITORY/.git/MERGE_HEAD" && ! -e "$REPOSITORY/.git/CHERRY_PICK_HEAD" &&
		! -d "$REPOSITORY/.git/rebase-merge" && ! -d "$REPOSITORY/.git/rebase-apply" ]] ||
		die 'an existing merge, cherry-pick, or rebase transaction must be resolved before a source commit'

	for raw in "$@"; do
		[[ -n "$raw" && "$raw" != *$'\n'* && "$raw" != *$'\r'* ]] || die 'commit paths must be nonempty single lines'
		if [[ "$raw" == /* ]]; then
			[[ "$raw" == "$REPOSITORY/"* ]] || die "commit path is outside the repository: $raw"
			path="${raw#"$REPOSITORY/"}"
		else
			path="${raw#./}"
		fi
		absolute="$(realpath -m "$REPOSITORY/$path")"
		[[ "$absolute" == "$REPOSITORY/"* && "$absolute" != "$REPOSITORY" ]] || die "invalid repository commit path: $raw"
		path="${absolute#"$REPOSITORY/"}"
		[[ ! -d "$absolute" ]] || die "commit paths must name files, not directories: $path"
		if [[ ! -e "$absolute" && ! -L "$absolute" ]] && ! git -C "$REPOSITORY" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
			die "commit path is neither an existing file nor a tracked deletion: $path"
		fi
		agent_commit_path_is_generated "$path" && die "generated/build/binary artifact cannot be committed: $path"
		agent_commit_path_is_source_related "$path" || die "path is not a recognized source or source-related artifact: $path"
		agent_commit_path_in_scope "$path" "${AGENT_COMMIT_SCOPE:-}" || die "commit path is outside the assignment Allowed-Scope: $path"
		if [[ -e "$absolute" || -L "$absolute" ]]; then
			git -C "$REPOSITORY" check-ignore -q --no-index -- "$path" && die "ignored artifact cannot be committed: $path"
		fi
		[[ -z "${requested[$path]:-}" ]] || continue
		requested[$path]=1
		agent_commit_paths+=("$path")
	done

	trap 'agent_commit_unstage' ERR EXIT
	git -C "$REPOSITORY" add -A -- "${agent_commit_paths[@]}"
	while IFS= read -r staged_file; do
		[[ -n "$staged_file" ]] || continue
		[[ -n "${requested[$staged_file]:-}" ]] || die "Git staged an undeclared path: $staged_file"
		add_count=$((add_count + 1))
	done < <(git -C "$REPOSITORY" diff --cached --name-only -- "${agent_commit_paths[@]}")
	(( add_count > 0 )) || die 'none of the declared paths has a change to commit'
	if git -C "$REPOSITORY" diff --cached --numstat -- "${agent_commit_paths[@]}" | awk '$1 == "-" || $2 == "-" {found=1} END {exit !found}'; then
		die 'binary content cannot be committed by an agent source transaction'
	fi
	if git -C "$REPOSITORY" ls-files --stage -- "${agent_commit_paths[@]}" | awk '$1 == "160000" {found=1} END {exit !found}'; then
		die 'submodule/gitlink entries cannot be committed by an agent source transaction'
	fi
	git -C "$REPOSITORY" diff --cached --check -- "${agent_commit_paths[@]}"
	git -C "$REPOSITORY" -c commit.gpgSign=false commit --no-verify -F "$message_file" -- "${agent_commit_paths[@]}" >/dev/null
	trap - ERR EXIT
	commit="$(git -C "$REPOSITORY" rev-parse HEAD)"
	printf '%s\n' "$commit"
}
