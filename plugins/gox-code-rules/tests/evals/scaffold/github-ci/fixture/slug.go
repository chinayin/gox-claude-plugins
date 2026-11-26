// Package slug turns a title into a URL path segment.
package slug

import (
	"strings"
	"unicode"
)

// Make lowercases s and joins its letter and digit runs with hyphens.
func Make(s string) string {
	fields := strings.FieldsFunc(strings.ToLower(s), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
	return strings.Join(fields, "-")
}
