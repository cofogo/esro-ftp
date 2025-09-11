package internal

import (
	"os"
	"strings"
)

// IsDebugMode checks if we're in debug mode
func IsDebugMode() bool {
	debug := os.Getenv("DEBUG")
	return strings.ToLower(debug) == "true"
}
