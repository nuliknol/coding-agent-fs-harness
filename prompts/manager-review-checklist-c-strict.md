## Strict C verification profile

Apply this checklist during this first full-repository review. It supplements
the governing specification and development policy; it does not authorize new
product requirements, source edits, package installation, or production
hardening.

Run the actual program and batch every reproducible finding into this review.
Record the important command, exit status, and relevant output. If the
repository exposes equivalent project-specific commands, use those rather than
assuming Make targets. Preserve required include, define, library, and pthread
flags when changing compiler options.

1. **Baseline build and behavior**
   - Perform a clean canonical build using the repository's documented command.
   - Run its existing test target and the smallest public-interface smoke test
     that exercises the principal feature.
   - Treat missing documented verification, build failures, test failures, and
     disconnected public-path behavior as findings when required by the
     specification or policy.

2. **Optimized warnings-as-errors build**
   - Rebuild from clean state with optimization enabled and strict diagnostics,
     normally `-O2 -std=c11 -Wall -Wextra -Werror -pedantic`, plus every
     project-required flag.
   - Exercise the resulting optimized binary. Compiler warnings, optimizer-only
     failures, or behavior changes are findings.

3. **ASan/UBSan execution**
   - When supported by the compiler and platform, rebuild cleanly with
     `-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer` and the
     project's required flags.
   - Run the project tests and focused public-interface smoke under the
     instrumented binary. Treat reproducible sanitizer diagnostics, leaks
     reported by the configured sanitizer, crashes, or hangs as findings.
   - If sanitizers are unavailable or incompatible with the environment, mark
     the check as skipped with the concrete reason; tool absence alone is not a
     product defect.

4. **Independent static analysis**
   - If already installed and compatible with the project, run one independent
     analyzer such as `clang --analyze`, `scan-build`, `clang-tidy` with a
     compile database, or `cppcheck`.
   - Triage results against reachable source behavior. Report actionable
     correctness, lifetime, bounds, nullability, or concurrency findings; do
     not reject for unverified style warnings or because an optional analyzer
     is absent. Do not install tools.

5. **Lexer and parser edge cases, when applicable**
   - Probe empty input and empty tokens/strings, boundary-length input,
     malformed and unterminated constructs, punctuation classification,
     whitespace/control characters, invalid bytes, and location tracking.
   - For grammar or recursive recognizers, exercise epsilon and nested nullable
     expansion, right recursion, ambiguous alternatives, full-input
     consumption, deterministic deduplication, and termination on invalid or
     cyclic input.
   - Derive the exact probes from the specification. Mark an item not
     applicable rather than inventing a lexer or parser requirement.

6. **Output and exit contracts**
   - Verify success, rejection, command-line failure, and malformed-input exit
     statuses required by the specification.
   - Verify every contract that requires one output line with newline-bearing
     or control-character-bearing user input. Ensure diagnostics remain
     escaped, deterministic, nonempty where required, and free of
     scheduling-dependent text.

7. **Acceptance state**
   - Restore or confirm a clean canonical build after specialized analyzer or
     sanitizer builds.
   - Accept only if the specification is implemented and all applicable
     mandatory checks pass. Optional-tool skips must be disclosed in acceptance
     evidence.

Do not repeat this complete profile automatically in later review cycles.
Later reviews should verify the published addenda, their focused regressions,
and any behavior affected by the worker's corrections.
