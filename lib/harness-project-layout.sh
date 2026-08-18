#!/usr/bin/env bash

# Canonical project and task identities.  Keeping these names in one module
# prevents command scripts from reconstructing durable artifact paths.

project_dir()
{
	printf '%s/projects/%s' "$HARNESS_ROOT" "$PROJECT"
}

project_tmp_dir()
{
	printf '%s\n' "$PROJECT_TMP_DIR"
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

