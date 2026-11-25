package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"unicode/utf8"

	"github.com/betterleaks/betterleaks/config"
	"github.com/betterleaks/betterleaks/detect"
	"github.com/betterleaks/betterleaks/logging"
	blregexp "github.com/betterleaks/betterleaks/regexp"
	regexpre2 "github.com/betterleaks/betterleaks/regexp/re2"
	"github.com/betterleaks/betterleaks/sources"
)

const (
	engineModule  = "github.com/betterleaks/betterleaks"
	engineVersion = "v1.10.1"
	version       = "dotfiles-betterleaks-staged protocol 1 engine " + engineVersion
	maxPathBytes  = 64 * 1024
	maxBlobBytes  = 64 * 1024 * 1024
	findingExit   = 21
	incomplete    = 2

	// Match the official CLI configuration in check-sensitive-changes.mjs.
	scanConfig = "prefilter = \"false\"\n\n[extend]\nuseDefault = true\n"
)

var errFrame = errors.New("invalid staged scanner input")

// Only these result fields cross back into the caller. The scanner's finding
// objects can hold the candidate path, line text, and detected value.
type finding struct {
	RuleID    string
	StartLine int
}

func readFrame(input io.Reader) (string, []byte, error) {
	// Both lengths are uint32 big endian, followed by the UTF-8 path and blob.
	// Reading exactly the declared sizes keeps binary contents opaque.
	var header [8]byte
	if _, err := io.ReadFull(input, header[:]); err != nil {
		return "", nil, errFrame
	}
	pathSize := binary.BigEndian.Uint32(header[:4])
	blobSize := binary.BigEndian.Uint32(header[4:])
	if pathSize == 0 || pathSize > maxPathBytes || blobSize > maxBlobBytes {
		return "", nil, errFrame
	}
	file := make([]byte, pathSize)
	if _, err := io.ReadFull(input, file); err != nil || !utf8.Valid(file) || bytes.IndexByte(file, 0) >= 0 {
		return "", nil, errFrame
	}
	blob := make([]byte, blobSize)
	if _, err := io.ReadFull(input, blob); err != nil {
		return "", nil, errFrame
	}
	var trailing [1]byte
	if _, err := io.ReadFull(input, trailing[:]); err != io.EOF {
		return "", nil, errFrame
	}
	return string(file), blob, nil
}

func pinnedEngine() bool {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return false
	}
	for _, dep := range info.Deps {
		if dep.Path == engineModule {
			return dep.Version == engineVersion && dep.Replace == nil
		}
	}
	return false
}

func scan(ctx context.Context, file string, blob []byte) ([]finding, error) {
	// The version-pinned engine in the official CLI selects RE2 before loading
	// configuration. No configuration or ignore files are loaded from the input.
	blregexp.SetEngine(regexpre2.RE2{})
	cfg, err := config.ParseTOML([]byte(scanConfig), "")
	if err != nil {
		return nil, err
	}
	detector := detect.NewDetectorContext(ctx, cfg, detect.ValidationOptions{})
	detector.IgnoreGitleaksAllow = true
	detector.MaxDecodeDepth = 2
	detector.MaxArchiveDepth = 8
	source := &sources.Stdin{
		Content:         bytes.NewReader(blob),
		Attributes:      map[string]string{sources.AttrPath: file},
		ShouldSkip:      detector.SkipFunc(),
		MaxArchiveDepth: detector.MaxArchiveDepth,
	}
	results, err := detector.DetectSource(ctx, source)
	if err != nil {
		return nil, err
	}
	rows := make([]finding, 0, len(results))
	for _, result := range detector.FilterByStatus(results) {
		rows = append(rows, finding{RuleID: result.RuleID, StartLine: result.StartLine})
	}
	return rows, nil
}

func run(args []string, input io.Reader, output io.Writer) int {
	if !pinnedEngine() {
		return incomplete
	}
	if len(args) == 1 && args[0] == "--version" {
		if _, err := fmt.Fprintln(output, version); err != nil {
			return incomplete
		}
		return 0
	}
	if len(args) != 0 {
		return incomplete
	}
	file, blob, err := readFrame(input)
	if err != nil {
		return incomplete
	}
	rows, err := scan(context.Background(), file, blob)
	if err != nil {
		return incomplete
	}
	if err := json.NewEncoder(output).Encode(rows); err != nil {
		return incomplete
	}
	if len(rows) != 0 {
		return findingExit
	}
	return 0
}

func main() {
	// The upstream logger can include candidate names in its diagnostics.
	logging.Logger = logging.Logger.Output(io.Discard)
	code := run(os.Args[1:], os.Stdin, os.Stdout)
	if code == incomplete {
		fmt.Fprintln(os.Stderr, "Staged scanner could not complete the scan.")
	}
	os.Exit(code)
}
