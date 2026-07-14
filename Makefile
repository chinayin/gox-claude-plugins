#  local dev tasks (no CI; run these by hand).
#
#   make deps      install jq + bats-core
#   make validate  jq-validate every manifest + the project-settings template
#   make test      run all bats: central cross-plugin + each plugin's own tests
#   make eval      reminder: skill trigger-rate is a manual skill-creator eval

.PHONY: deps validate test eval

deps:
	brew install jq bats-core

validate:
	@for f in .claude-plugin/marketplace.json templates/project-settings.json plugins/*/.claude-plugin/plugin.json; do jq -e . "$$f" >/dev/null && echo "OK  $$f" || { echo "BAD $$f"; exit 1; }; done

test:
	bats tests plugins/*/tests

eval:
	@echo "Skill trigger/hit rate is not a bats gate — run skill-creator eval"
	@echo "(with-plugin vs baseline on real prompts), e.g. token-thrift:delegate"
	@echo "on token-heavy 'read Feishu / wide search' prompts. See docs/DESIGN.md."
