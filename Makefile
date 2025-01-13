.PHONY: test lint docs

test:
	bash tests/run.sh

# syntax check only; run shellcheck on top of this if you have it
lint:
	for f in bin/*.sh tests/*.sh; do bash -n $$f || exit 1; done

# regenerate docs/usage.md after changing any script's --help text
docs:
	tools/gen-usage.sh > docs/usage.md
