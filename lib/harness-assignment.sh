#!/usr/bin/env bash

harness_assignment_replace_metadata()
{
	local file="$1" field="$2" value="$3" temporary count
	[[ "$field" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]] || die "invalid assignment metadata field: $field"
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "assignment metadata value must be one line: $field"
	count="$(grep -Ec "^${field}:" "$file" || true)"
	(( count == 1 )) || die "assignment metadata field must occur exactly once before replacement: $field"
	temporary="${file}.metadata.$$.$RANDOM"
	awk -v field="$field" -v value="$value" '
		index($0, field ":") == 1 {if(!seen++) print field ": " value; next}
		{print}
	' "$file" > "$temporary"
	chmod 600 "$temporary"
	mv -f -- "$temporary" "$file"
}

harness_assignment_publish()
{
	local temporary="$1" ready="$2"
	[[ -f "$temporary" ]] || die "assignment publication source is missing: $temporary"
	[[ ! -e "$ready" ]] || die "assignment publication target already exists: $ready"
	chmod 600 "$temporary"
	mv -- "$temporary" "$ready"
}

