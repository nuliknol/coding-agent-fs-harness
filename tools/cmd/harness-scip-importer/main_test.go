package main

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	"github.com/scip-code/scip/bindings/go/scip"
)

func TestEnsureFileReturnsStableIDAfterConflict(t *testing.T) {
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`
		CREATE TABLE files (
			file_id INTEGER PRIMARY KEY,
			generation_id TEXT NOT NULL,
			repository_path TEXT NOT NULL,
			language TEXT,
			content_sha256 TEXT,
			tracked INTEGER NOT NULL,
			generated INTEGER NOT NULL,
			UNIQUE(generation_id, repository_path)
		);
		CREATE TABLE unrelated (unrelated_id INTEGER PRIMARY KEY);`); err != nil {
		t.Fatal(err)
	}
	imp := &importer{ctx: ctx, tx: tx, generation: "generation"}
	first, err := imp.ensureFile("src/repeated.c", "c", "first", false)
	if err != nil {
		t.Fatal(err)
	}
	for count := 0; count < 20; count++ {
		if _, err := tx.Exec("INSERT INTO unrelated DEFAULT VALUES"); err != nil {
			t.Fatal(err)
		}
	}
	second, err := imp.ensureFile("src/repeated.c", "c", "second", false)
	if err != nil {
		t.Fatal(err)
	}
	if second != first {
		t.Fatalf("conflicting document changed file id: first=%d second=%d", first, second)
	}
}

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

func TestTestDefinitionRejectsLocalAndNonCallableSymbols(t *testing.T) {
	if isTestDefinition("tests/test_calc.c", "local 0", nil) {
		t.Fatal("local definition was classified as a test")
	}
	variable := &scip.SymbolInformation{Kind: scip.SymbolInformation_Variable}
	if isTestDefinition("tests/test_calc.c", "scip symbol variable.", variable) {
		t.Fatal("test-file variable was classified as a test")
	}
	function := &scip.SymbolInformation{Kind: scip.SymbolInformation_Function}
	if !isTestDefinition("tests/test_calc.c", "scip symbol main().", function) {
		t.Fatal("test function was not classified as a test")
	}
	if isTestDefinition("src/calc.c", "scip symbol main().", function) {
		t.Fatal("ordinary source function was classified as a test")
	}
	unspecified := &scip.SymbolInformation{}
	if !isTestDefinition("tests/test_calc.c", "main", unspecified) {
		t.Fatal("test main with an omitted SCIP kind was not classified as a test")
	}
}
