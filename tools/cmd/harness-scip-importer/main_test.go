package main

import (
	"strings"
	"testing"

	"github.com/scip-code/scip/bindings/go/scip"
)

func TestExpandStructuralRangeFunction(t *testing.T) {
	source := []byte(`static int bounded(int value)
{
    const char *brace = "}";
    /* } does not close the function */
    if (value) { return 1; }
    return 0;
}

int unrelated(void) { return 9; }
`)
	original := scip.Range{
		Start: scip.Position{Line: 0, Character: 11},
		End:   scip.Position{Line: 0, Character: 18},
	}
	expanded := expandStructuralRange(source, original, 65536)
	text := sourceRegionText(source, expanded, 65536)
	if !strings.Contains(text, "return 0;") {
		t.Fatalf("function body was not retained: %q", text)
	}
	if strings.Contains(text, "unrelated") {
		t.Fatalf("structural range crossed into the next function: %q", text)
	}
}

func TestExpandStructuralRangeDeclaration(t *testing.T) {
	source := []byte("int declared(int value);\nint next_value;\n")
	original := scip.Range{
		Start: scip.Position{Line: 0, Character: 4},
		End:   scip.Position{Line: 0, Character: 12},
	}
	text := sourceRegionText(source, expandStructuralRange(source, original, 65536), 65536)
	if !strings.Contains(text, "int declared(int value);") || strings.Contains(text, "next_value") {
		t.Fatalf("declaration boundary is incorrect: %q", text)
	}
}

func TestExpandStructuralRangeMacro(t *testing.T) {
	source := []byte("#define ADD(left, right) \\\n+    ((left) + (right))\nint after;\n")
	original := scip.Range{
		Start: scip.Position{Line: 0, Character: 8},
		End:   scip.Position{Line: 0, Character: 11},
	}
	text := sourceRegionText(source, expandStructuralRange(source, original, 65536), 65536)
	if !strings.Contains(text, "((left) + (right))") || strings.Contains(text, "int after") {
		t.Fatalf("macro boundary is incorrect: %q", text)
	}
}
