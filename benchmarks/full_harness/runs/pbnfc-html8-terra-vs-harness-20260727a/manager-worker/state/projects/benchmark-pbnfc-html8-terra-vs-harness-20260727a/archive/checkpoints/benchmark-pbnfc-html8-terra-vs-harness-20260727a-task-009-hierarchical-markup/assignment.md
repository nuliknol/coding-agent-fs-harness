# Hierarchical HTML grammar integration, rejection diagnostics, and stress cases

Task-ID: 009-hierarchical-markup
Project-Plan-Item: 009
Root-Criterion: p009.hierarchical-markup-acceptance
Root-Criterion: p009.hierarchical-rejection-diagnostics
Root-Criterion: p009.hierarchical-stress-repeatability
Execution-Mode: LEAF_GOAL
Goal-ID: p009.goal.hierarchical-markup-acceptance
Target-Criterion: p009.hierarchical-markup-acceptance
Goal-Success-Evidence: the public CLI accepts a compact nested document using the specified hierarchical grammar, including nested tags, attributes, text, and self-closing img.
Focused-Validation: Run make test-hierarchical-markup-core.
Allowed-Scope: src/main.c, src/markup_lexer.c, src/recognizer.c, tests/hierarchical_markup_smoke.c, and its Makefile target only.
Baseline-Boundary: items 001–008 are accepted, including public parallel recognition and optional worker statistics; mismatch diagnostics and stress coverage remain unverified.
Hard-Block-Conditions: None expected; repository-local integration or focused-test work must be resolved within scope.

Implement and prove only the acceptance criterion. Preserve the public CLI contract and do not broaden to rejection diagnostics or stress/repetition work yet.
