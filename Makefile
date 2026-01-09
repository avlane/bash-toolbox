.PHONY: test test-verbose lint docs

test:
	bash tests/run.sh

# make test-verbose, or run tests/run.sh -h style options directly:
#   tests/run.sh -f dry_run retry
test-verbose:
	bash tests/run.sh -v

# syntax check only; run shellcheck on top of this if you have it
lint:
	for f in bin/*.sh tests/*.sh; do bash -n $$f || exit 1; done

# regenerate docs/usage.md after changing any script's --help text
docs:
	tools/gen-usage.sh > docs/usage.md
