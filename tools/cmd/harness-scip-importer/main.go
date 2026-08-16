package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	_ "github.com/mattn/go-sqlite3"
	"github.com/scip-code/scip/bindings/go/scip"
	"google.golang.org/protobuf/proto"
)

type counters struct {
	documents     int
	files         int
	symbols       int
	definitions   int
	references    int
	relationships int
	lexicalUnits  int
	skippedDocs   int
}

type importer struct {
	ctx         context.Context
	tx          *sql.Tx
	generation  string
	repository  string
	projectRoot string
	counts      counters
	seenSymbols map[string]struct{}
	unresolved  []unresolvedDocument
}

type unresolvedDocument struct {
	path   string
	reason string
}

type definitionRange struct {
	symbol string
	range_ scip.Range
}

const importerVersion = "harness-scip-importer schema-v5"

func main() {
	showVersion := flag.Bool("version", false, "print importer version")
	indexPath := flag.String("index", "", "SCIP index path")
	databasePath := flag.String("database", "", "canonical SQLite database path")
	generation := flag.String("generation", "", "repository-index generation ID")
	repository := flag.String("repository", "", "repository root")
	reportPath := flag.String("report", "", "summary TSV output path")
	unresolvedReportPath := flag.String("unresolved-report", "", "unresolved SCIP document TSV output path")
	flag.Parse()
	if *showVersion {
		fmt.Println(importerVersion)
		return
	}

	if *indexPath == "" || *databasePath == "" || *generation == "" || *repository == "" || *reportPath == "" {
		fmt.Fprintln(os.Stderr, "all of --index, --database, --generation, --repository, and --report are required")
		os.Exit(2)
	}

	repo, err := filepath.Abs(*repository)
	if err != nil {
		fatal(err)
	}
	db, err := sql.Open("sqlite3", "file:"+*databasePath+"?_foreign_keys=on")
	if err != nil {
		fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		fatal(err)
	}
	imp := &importer{
		ctx: ctx, tx: tx, generation: *generation, repository: filepath.Clean(repo),
		seenSymbols: make(map[string]struct{}),
	}
	if err := imp.verifyGeneration(); err != nil {
		_ = tx.Rollback()
		fatal(err)
	}
	if err := streamSCIP(*indexPath, imp.consumeMetadata, imp.consumeDocument, imp.consumeExternalSymbol); err != nil {
		_ = tx.Rollback()
		fatal(err)
	}
	if imp.projectRoot == "" {
		_ = tx.Rollback()
		fatal(errors.New("SCIP index omitted metadata.project_root"))
	}
	if err := tx.Commit(); err != nil {
		fatal(err)
	}
	if err := writeReport(*reportPath, imp.counts); err != nil {
		fatal(err)
	}
	if *unresolvedReportPath != "" {
		if err := writeUnresolvedReport(*unresolvedReportPath, imp.unresolved); err != nil {
			fatal(err)
		}
	}
}

func fatal(err error) {
	fmt.Fprintf(os.Stderr, "harness-scip-importer: %v\n", err)
	os.Exit(1)
}

func (i *importer) verifyGeneration() error {
	var count int
	if err := i.tx.QueryRowContext(i.ctx,
		"SELECT count(*) FROM index_generations WHERE generation_id=? AND status='READY'", i.generation).Scan(&count); err != nil {
		return err
	}
	if count != 1 {
		return fmt.Errorf("database does not contain READY generation %s", i.generation)
	}
	return nil
}

func (i *importer) consumeMetadata(metadata *scip.Metadata) error {
	root := metadata.GetProjectRoot()
	parsed, err := url.Parse(root)
	if err != nil {
		return fmt.Errorf("parse SCIP project root: %w", err)
	}
	if parsed.Scheme != "file" {
		return fmt.Errorf("unsupported SCIP project-root scheme %q", parsed.Scheme)
	}
	path, err := url.PathUnescape(parsed.Path)
	if err != nil {
		return fmt.Errorf("decode SCIP project root: %w", err)
	}
	i.projectRoot = filepath.Clean(filepath.FromSlash(path))
	return nil
}

func (i *importer) consumeExternalSymbol(info *scip.SymbolInformation) error {
	return i.upsertSymbol("", "", info.GetSymbol(), info)
}

func (i *importer) consumeDocument(document *scip.Document) error {
	i.counts.documents++
	relPath, absPath, err := i.resolveDocumentPath(document.GetRelativePath())
	if err != nil {
		i.counts.skippedDocs++
		i.unresolved = append(i.unresolved, unresolvedDocument{
			path: document.GetRelativePath(), reason: err.Error(),
		})
		return nil
	}
	content, readErr := os.ReadFile(absPath)
	contentHash := ""
	if readErr == nil {
		sum := sha256.Sum256(content)
		contentHash = hex.EncodeToString(sum[:])
	}
	generated := false
	for _, occurrence := range document.GetOccurrences() {
		if hasRole(occurrence, scip.SymbolRole_Generated) {
			generated = true
			break
		}
	}
	result, err := i.tx.ExecContext(i.ctx, `
		INSERT INTO files(generation_id, repository_path, language, content_sha256, tracked, generated)
		VALUES(?, ?, ?, ?, 1, ?)
		ON CONFLICT(generation_id, repository_path) DO UPDATE SET
			language=excluded.language, content_sha256=excluded.content_sha256, generated=excluded.generated`,
		i.generation, filepath.ToSlash(relPath), document.GetLanguage(), contentHash, boolInt(generated))
	if err != nil {
		return err
	}
	fileID, err := result.LastInsertId()
	if err != nil || fileID == 0 {
		if err := i.tx.QueryRowContext(i.ctx,
			"SELECT file_id FROM files WHERE generation_id=? AND repository_path=?",
			i.generation, filepath.ToSlash(relPath)).Scan(&fileID); err != nil {
			return err
		}
	}
	i.counts.files++

	infoBySymbol := make(map[string]*scip.SymbolInformation)
	for _, info := range document.GetSymbols() {
		canonical := canonicalSymbol(relPath, info.GetSymbol())
		infoBySymbol[canonical] = info
		if err := i.upsertSymbol(relPath, document.GetLanguage(), info.GetSymbol(), info); err != nil {
			return err
		}
	}
	for _, occurrence := range document.GetOccurrences() {
		if occurrence.GetSymbol() == "" {
			continue
		}
		canonical := canonicalSymbol(relPath, occurrence.GetSymbol())
		if _, ok := infoBySymbol[canonical]; !ok {
			if err := i.upsertSymbol(relPath, document.GetLanguage(), occurrence.GetSymbol(), nil); err != nil {
				return err
			}
		}
	}

	definitions := make([]definitionRange, 0)
	for _, occurrence := range document.GetOccurrences() {
		if occurrence.GetSymbol() == "" || !hasRole(occurrence, scip.SymbolRole_Definition) {
			continue
		}
		if strings.HasPrefix(occurrence.GetSymbol(), "local ") ||
			strings.Contains(occurrence.GetSymbol(), "`<file>") {
			continue
		}
		range_, ok := occurrence.EnclosingSourceRange()
		if !ok {
			range_, ok = occurrence.SourceRange()
		}
		if ok {
			definitions = append(definitions, definitionRange{
				symbol: canonicalSymbol(relPath, occurrence.GetSymbol()), range_: range_,
			})
		}
	}

	for _, occurrence := range document.GetOccurrences() {
		if occurrence.GetSymbol() == "" {
			continue
		}
		if err := i.importOccurrence(fileID, relPath, content, occurrence, definitions); err != nil {
			return err
		}
	}
	for _, info := range document.GetSymbols() {
		if err := i.importRelationships(relPath, document.GetLanguage(), info); err != nil {
			return err
		}
	}
	return nil
}

func (i *importer) resolveDocumentPath(relative string) (string, string, error) {
	if i.projectRoot == "" {
		return "", "", errors.New("SCIP metadata must precede documents")
	}
	abs := filepath.Clean(filepath.Join(i.projectRoot, filepath.FromSlash(relative)))
	rel, err := filepath.Rel(i.repository, abs)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", "", fmt.Errorf("SCIP document lies outside repository: %s", abs)
	}
	return filepath.ToSlash(rel), abs, nil
}

func (i *importer) upsertSymbol(documentPath, language, raw string, info *scip.SymbolInformation) error {
	if raw == "" {
		return nil
	}
	canonical := canonicalSymbol(documentPath, raw)
	display := displayName(raw, info)
	kind := "UNSPECIFIED"
	packageName := ""
	if info != nil {
		kind = info.GetKind().String()
	}
	if parsed, err := scip.ParseSymbol(raw); err == nil && parsed.GetPackage() != nil {
		packageName = parsed.GetPackage().GetName()
	}
	_, err := i.tx.ExecContext(i.ctx, `
		INSERT INTO symbols(symbol_id, generation_id, display_name, symbol_kind, language, package_name, provider)
		VALUES(?, ?, ?, ?, ?, ?, 'scip-clang')
		ON CONFLICT(symbol_id) DO UPDATE SET
			display_name=CASE WHEN excluded.display_name != '' THEN excluded.display_name ELSE symbols.display_name END,
			symbol_kind=CASE WHEN excluded.symbol_kind != 'UNSPECIFIED' THEN excluded.symbol_kind ELSE symbols.symbol_kind END,
			language=CASE WHEN excluded.language != '' THEN excluded.language ELSE symbols.language END,
			package_name=CASE WHEN excluded.package_name != '' THEN excluded.package_name ELSE symbols.package_name END`,
		canonical, i.generation, display, kind, language, packageName)
	if err != nil {
		return err
	}
	if _, seen := i.seenSymbols[canonical]; !seen {
		i.seenSymbols[canonical] = struct{}{}
		i.counts.symbols++
	}
	return nil
}

func (i *importer) importOccurrence(fileID int64, documentPath string, content []byte,
	occurrence *scip.Occurrence, definitions []definitionRange) error {
	range_, ok := occurrence.SourceRange()
	if !ok {
		return nil
	}
	regionRange := range_
	regionKind := "symbol_reference"
	definition := hasRole(occurrence, scip.SymbolRole_Definition)
	if definition {
		regionKind = "symbol_definition"
		if enclosing, ok := occurrence.EnclosingSourceRange(); ok {
			regionRange = enclosing
		}
		regionRange = expandStructuralRange(content, regionRange, 65536)
	}
	regionID, err := i.ensureRegion(fileID, regionKind, displayName(occurrence.GetSymbol(), nil), regionRange)
	if err != nil {
		return err
	}
	symbol := canonicalSymbol(documentPath, occurrence.GetSymbol())
	if definition {
		kind := "definition"
		if hasRole(occurrence, scip.SymbolRole_ForwardDefinition) {
			kind = "forward_definition"
		}
		if _, err := i.tx.ExecContext(i.ctx,
			"INSERT OR IGNORE INTO symbol_definitions(symbol_id, region_id, definition_kind, provider) VALUES(?, ?, ?, 'scip-clang')",
			symbol, regionID, kind); err != nil {
			return err
		}
		i.counts.definitions++
		text := sourceRegionText(content, regionRange, 65536)
		if text != "" {
			documentID := stableID(documentPath, symbol, regionRange.String())
			if _, err := i.tx.ExecContext(i.ctx,
				"INSERT INTO lexical_documents(document_id, repository_path, symbol_name, document_kind, content) VALUES(?, ?, ?, 'symbol_definition', ?)",
				documentID, documentPath, displayName(occurrence.GetSymbol(), nil), text); err != nil {
				return err
			}
			i.counts.lexicalUnits++
		}
		if isTestPath(documentPath) {
			testID := stableID("test", documentPath, symbol)
			if _, err := i.tx.ExecContext(i.ctx,
				"INSERT OR IGNORE INTO tests(test_id, generation_id, name, file_id, region_id, provider) VALUES(?, ?, ?, ?, ?, 'scip-clang')",
				testID, i.generation, displayName(occurrence.GetSymbol(), nil), fileID, regionID); err != nil {
				return err
			}
			if _, err := i.tx.ExecContext(i.ctx,
				"INSERT OR IGNORE INTO test_symbol_edges(test_id, symbol_id, edge_kind, provider) VALUES(?, ?, 'DEFINES', 'scip-clang')",
				testID, symbol); err != nil {
				return err
			}
		}
		return nil
	}

	referenceKind := roleDescription(occurrence)
	if _, err := i.tx.ExecContext(i.ctx,
		"INSERT OR IGNORE INTO symbol_references(symbol_id, region_id, reference_kind, provider) VALUES(?, ?, ?, 'scip-clang')",
		symbol, regionID, referenceKind); err != nil {
		return err
	}
	i.counts.references++
	if owner := enclosingDefinition(definitions, range_.Start); owner != "" && owner != symbol {
		if _, err := i.tx.ExecContext(i.ctx, `
			INSERT OR IGNORE INTO symbol_edges(source_symbol_id, target_symbol_id, edge_kind, provider, confidence, evidence_region_id)
			VALUES(?, ?, 'REFERENCES', 'scip-clang', 'AUTHORITATIVE', ?)`, owner, symbol, regionID); err != nil {
			return err
		}
		if isTestPath(documentPath) {
			testID := stableID("test", documentPath, owner)
			if _, err := i.tx.ExecContext(i.ctx, `
				INSERT OR IGNORE INTO test_symbol_edges(test_id, symbol_id, edge_kind, provider)
				SELECT ?, ?, 'REFERENCES', 'scip-clang'
				WHERE EXISTS (SELECT 1 FROM tests WHERE test_id=?)`, testID, symbol, testID); err != nil {
				return err
			}
		}
	}
	return nil
}

func (i *importer) importRelationships(documentPath, language string, info *scip.SymbolInformation) error {
	source := canonicalSymbol(documentPath, info.GetSymbol())
	for _, relationship := range info.GetRelationships() {
		target := canonicalSymbol(documentPath, relationship.GetSymbol())
		if err := i.upsertSymbol(documentPath, language, relationship.GetSymbol(), nil); err != nil {
			return err
		}
		kinds := make([]string, 0, 4)
		if relationship.GetIsReference() {
			kinds = append(kinds, "RELATED_REFERENCE")
		}
		if relationship.GetIsImplementation() {
			kinds = append(kinds, "IMPLEMENTS")
		}
		if relationship.GetIsTypeDefinition() {
			kinds = append(kinds, "TYPE_DEFINITION")
		}
		if relationship.GetIsDefinition() {
			kinds = append(kinds, "RELATED_DEFINITION")
		}
		for _, kind := range kinds {
			if _, err := i.tx.ExecContext(i.ctx, `
				INSERT OR IGNORE INTO symbol_edges(source_symbol_id, target_symbol_id, edge_kind, provider, confidence)
				VALUES(?, ?, ?, 'scip-clang', 'AUTHORITATIVE')`, source, target, kind); err != nil {
				return err
			}
			if kind == "TYPE_DEFINITION" {
				if _, err := i.tx.ExecContext(i.ctx, `
					INSERT OR IGNORE INTO type_edges(source_symbol_id, type_symbol_id, edge_kind, provider)
					VALUES(?, ?, 'TYPE_DEFINITION', 'scip-clang')`, source, target); err != nil {
					return err
				}
			}
			i.counts.relationships++
		}
	}
	return nil
}

func (i *importer) ensureRegion(fileID int64, kind, name string, range_ scip.Range) (int64, error) {
	startLine := int64(range_.Start.Line) + 1
	endLine := int64(range_.End.Line) + 1
	_, err := i.tx.ExecContext(i.ctx, `
		INSERT OR IGNORE INTO source_regions(
			file_id, region_kind, name, start_line, start_column, end_line, end_column, provider
		) VALUES(?, ?, ?, ?, ?, ?, ?, 'scip-clang')`,
		fileID, kind, name, startLine, range_.Start.Character, endLine, range_.End.Character)
	if err != nil {
		return 0, err
	}
	var regionID int64
	err = i.tx.QueryRowContext(i.ctx, `
		SELECT region_id FROM source_regions
		WHERE file_id=? AND region_kind=? AND start_line=? AND start_column=? AND end_line=? AND end_column=? AND provider='scip-clang'`,
		fileID, kind, startLine, range_.Start.Character, endLine, range_.End.Character).Scan(&regionID)
	return regionID, err
}

func streamSCIP(path string, metadataFn func(*scip.Metadata) error,
	documentFn func(*scip.Document) error, externalFn func(*scip.SymbolInformation) error) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	reader := bufio.NewReaderSize(file, 256*1024)
	for {
		tag, err := binary.ReadUvarint(reader)
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("read SCIP field tag: %w", err)
		}
		fieldNumber := tag >> 3
		wireType := tag & 7
		if wireType != 2 {
			if err := skipWireValue(reader, wireType); err != nil {
				return err
			}
			continue
		}
		length, err := binary.ReadUvarint(reader)
		if err != nil {
			return fmt.Errorf("read SCIP field length: %w", err)
		}
		if length > uint64(^uint(0)>>1) {
			return fmt.Errorf("SCIP field is too large: %d bytes", length)
		}
		payload := make([]byte, int(length))
		if _, err := io.ReadFull(reader, payload); err != nil {
			return fmt.Errorf("read SCIP field payload: %w", err)
		}
		switch fieldNumber {
		case 1:
			message := &scip.Metadata{}
			if err := proto.Unmarshal(payload, message); err != nil {
				return err
			}
			if err := metadataFn(message); err != nil {
				return err
			}
		case 2:
			message := &scip.Document{}
			if err := proto.Unmarshal(payload, message); err != nil {
				return err
			}
			if err := documentFn(message); err != nil {
				return err
			}
		case 3:
			message := &scip.SymbolInformation{}
			if err := proto.Unmarshal(payload, message); err != nil {
				return err
			}
			if err := externalFn(message); err != nil {
				return err
			}
		}
	}
}

func skipWireValue(reader *bufio.Reader, wireType uint64) error {
	switch wireType {
	case 0:
		_, err := binary.ReadUvarint(reader)
		return err
	case 1:
		_, err := io.CopyN(io.Discard, reader, 8)
		return err
	case 5:
		_, err := io.CopyN(io.Discard, reader, 4)
		return err
	default:
		return fmt.Errorf("unsupported protobuf wire type %d", wireType)
	}
}

func canonicalSymbol(documentPath, symbol string) string {
	if strings.HasPrefix(symbol, "local ") {
		return "local " + filepath.ToSlash(documentPath) + " " + strings.TrimPrefix(symbol, "local ")
	}
	return symbol
}

func displayName(raw string, info *scip.SymbolInformation) string {
	if info != nil && info.GetDisplayName() != "" {
		return info.GetDisplayName()
	}
	if parsed, err := scip.ParseSymbol(raw); err == nil {
		descriptors := parsed.GetDescriptors()
		if len(descriptors) > 0 {
			return descriptors[len(descriptors)-1].GetName()
		}
	}
	return raw
}

func hasRole(occurrence *scip.Occurrence, role scip.SymbolRole) bool {
	return occurrence.GetSymbolRoles()&int32(role) != 0
}

func roleDescription(occurrence *scip.Occurrence) string {
	roles := make([]string, 0, 4)
	if hasRole(occurrence, scip.SymbolRole_ReadAccess) {
		roles = append(roles, "READ")
	}
	if hasRole(occurrence, scip.SymbolRole_WriteAccess) {
		roles = append(roles, "WRITE")
	}
	if hasRole(occurrence, scip.SymbolRole_Import) {
		roles = append(roles, "IMPORT")
	}
	if hasRole(occurrence, scip.SymbolRole_Test) {
		roles = append(roles, "TEST")
	}
	if len(roles) == 0 {
		return "REFERENCE"
	}
	return strings.Join(roles, "+")
}

func enclosingDefinition(definitions []definitionRange, position scip.Position) string {
	best := ""
	var bestRange scip.Range
	for _, definition := range definitions {
		if !definition.range_.Contains(position) {
			continue
		}
		if best == "" || bestRange.Contains(definition.range_.Start) {
			best = definition.symbol
			bestRange = definition.range_
		}
	}
	if best != "" {
		return best
	}
	// Some SCIP producers expose only an identifier range instead of the full
	// function body as enclosing_range. For C/C++ documents, the nearest prior
	// non-local definition is a deterministic conservative owner approximation;
	// local declarations and synthetic <file> symbols were excluded above.
	for _, definition := range definitions {
		if definition.range_.Start.Line > position.Line ||
			(definition.range_.Start.Line == position.Line &&
				definition.range_.Start.Character > position.Character) {
			continue
		}
		if best == "" || bestRange.Start.Line < definition.range_.Start.Line ||
			(bestRange.Start.Line == definition.range_.Start.Line &&
				bestRange.Start.Character < definition.range_.Start.Character) {
			best = definition.symbol
			bestRange = definition.range_
		}
	}
	return best
}

func sourceRegionText(content []byte, range_ scip.Range, maximum int) string {
	if len(content) == 0 {
		return ""
	}
	lines := bytes.SplitAfter(content, []byte{'\n'})
	start := int(range_.Start.Line)
	end := int(range_.End.Line) + 1
	if start < 0 || start >= len(lines) {
		return ""
	}
	if end <= start {
		end = start + 1
	}
	if end > len(lines) {
		end = len(lines)
	}
	region := bytes.Join(lines[start:end], nil)
	if len(region) > maximum {
		region = region[:maximum]
	}
	return string(region)
}

// expandStructuralRange compensates for SCIP producers that emit only the
// identifier token as a definition's enclosing range. It recognizes one
// bounded C/C++ declaration, preprocessor definition, or balanced braced unit
// while ignoring delimiters inside comments and quoted literals. SCIP remains
// authoritative for the seed coordinate; this function only derives the
// structural excerpt boundary and never crosses the configured byte limit.
func expandStructuralRange(content []byte, original scip.Range, maximum int) scip.Range {
	if len(content) == 0 || maximum <= 0 {
		return original
	}
	lineStarts := []int{0}
	for index, value := range content {
		if value == '\n' && index+1 < len(content) {
			lineStarts = append(lineStarts, index+1)
		}
	}
	line := int(original.Start.Line)
	if line < 0 || line >= len(lineStarts) {
		return original
	}
	start := lineStarts[line]
	lineEnd := len(content)
	if line+1 < len(lineStarts) {
		lineEnd = lineStarts[line+1]
	}
	trimmed := bytes.TrimSpace(content[start:lineEnd])
	limit := start + maximum
	if limit > len(content) {
		limit = len(content)
	}
	if len(trimmed) > 0 && trimmed[0] == '#' {
		end := lineEnd
		for end < limit {
			previous := bytes.TrimRight(content[start:end], "\r\n")
			if len(previous) == 0 || previous[len(previous)-1] != '\\' {
				break
			}
			next := bytes.IndexByte(content[end:limit], '\n')
			if next < 0 {
				end = limit
				break
			}
			end += next + 1
		}
		return rangeForOffsets(lineStarts, start, maxInt(start, end-1), original)
	}

	const (
		normal = iota
		lineComment
		blockComment
		stringLiteral
		characterLiteral
	)
	state := normal
	escaped := false
	parenDepth := 0
	bracketDepth := 0
	braceDepth := 0
	sawBrace := false
	for cursor := start; cursor < limit; cursor++ {
		value := content[cursor]
		next := byte(0)
		if cursor+1 < limit {
			next = content[cursor+1]
		}
		switch state {
		case lineComment:
			if value == '\n' {
				state = normal
			}
			continue
		case blockComment:
			if value == '*' && next == '/' {
				state = normal
				cursor++
			}
			continue
		case stringLiteral, characterLiteral:
			if escaped {
				escaped = false
				continue
			}
			if value == '\\' {
				escaped = true
				continue
			}
			if (state == stringLiteral && value == '"') ||
				(state == characterLiteral && value == '\'') {
				state = normal
			}
			continue
		}
		if value == '/' && next == '/' {
			state = lineComment
			cursor++
			continue
		}
		if value == '/' && next == '*' {
			state = blockComment
			cursor++
			continue
		}
		if value == '"' {
			state = stringLiteral
			continue
		}
		if value == '\'' {
			state = characterLiteral
			continue
		}
		switch value {
		case '(':
			parenDepth++
		case ')':
			if parenDepth > 0 {
				parenDepth--
			}
		case '[':
			bracketDepth++
		case ']':
			if bracketDepth > 0 {
				bracketDepth--
			}
		case '{':
			if !sawBrace && parenDepth == 0 && bracketDepth == 0 {
				sawBrace = true
				braceDepth = 1
			} else if sawBrace {
				braceDepth++
			}
		case '}':
			if sawBrace && braceDepth > 0 {
				braceDepth--
				if braceDepth == 0 {
					end := cursor
					probe := cursor + 1
					for probe < limit && (content[probe] == ' ' || content[probe] == '\t' || content[probe] == '\r') {
						probe++
					}
					if probe < limit && content[probe] == ';' {
						end = probe
					}
					return rangeForOffsets(lineStarts, start, end, original)
				}
			}
		case ';':
			if !sawBrace && parenDepth == 0 && bracketDepth == 0 {
				return rangeForOffsets(lineStarts, start, cursor, original)
			}
		}
	}
	return original
}

func rangeForOffsets(lineStarts []int, start, inclusiveEnd int, fallback scip.Range) scip.Range {
	if inclusiveEnd < start {
		return fallback
	}
	endLine := 0
	for index, offset := range lineStarts {
		if offset > inclusiveEnd {
			break
		}
		endLine = index
	}
	return scip.Range{
		Start: scip.Position{Line: int32(indexOfLineStart(lineStarts, start)), Character: 0},
		End:   scip.Position{Line: int32(endLine), Character: int32(inclusiveEnd - lineStarts[endLine] + 1)},
	}
}

func indexOfLineStart(lineStarts []int, offset int) int {
	line := 0
	for index, start := range lineStarts {
		if start > offset {
			break
		}
		line = index
	}
	return line
}

func maxInt(left, right int) int {
	if left > right {
		return left
	}
	return right
}

func isTestPath(path string) bool {
	lower := strings.ToLower(filepath.ToSlash(path))
	base := strings.ToLower(filepath.Base(lower))
	return strings.Contains(lower, "/tests/") || strings.Contains(lower, "/test/") ||
		strings.HasPrefix(base, "test_") || strings.Contains(base, "_test.")
}

func stableID(parts ...string) string {
	hash := sha256.New()
	for _, part := range parts {
		_, _ = hash.Write([]byte(part))
		_, _ = hash.Write([]byte{0})
	}
	return hex.EncodeToString(hash.Sum(nil))
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func writeReport(path string, counts counters) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = fmt.Fprintf(file, "metric\tvalue\n"+
		"documents\t%d\nfiles\t%d\nsymbols\t%d\ndefinitions\t%d\nreferences\t%d\n"+
		"relationships\t%d\nlexical_units\t%d\nskipped_documents\t%d\n",
		counts.documents, counts.files, counts.symbols, counts.definitions, counts.references,
		counts.relationships, counts.lexicalUnits, counts.skippedDocs)
	return err
}

func writeUnresolvedReport(path string, unresolved []unresolvedDocument) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := fmt.Fprintln(file, "document_path\treason"); err != nil {
		return err
	}
	for _, item := range unresolved {
		pathValue := strings.NewReplacer("\t", " ", "\r", " ", "\n", " ").Replace(item.path)
		reason := strings.NewReplacer("\t", " ", "\r", " ", "\n", " ").Replace(item.reason)
		if _, err := fmt.Fprintf(file, "%s\t%s\n", pathValue, reason); err != nil {
			return err
		}
	}
	return nil
}
