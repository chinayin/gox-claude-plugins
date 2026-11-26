package slug

import "testing"

func TestMake(t *testing.T) {
	if got := Make("Hello, World 2"); got != "hello-world-2" {
		t.Fatalf("Make() = %q", got)
	}
}
