.PHONY: test demo record

# Run the test suite against a fresh demo repo.
test:
	zsh test/run.sh

# Build the demo repo in ~/wt-demo (or WT_DEMO_ROOT).
demo:
	demo/setup.sh $(WT_DEMO_ROOT)

# Record the README images with vhs (https://github.com/charmbracelet/vhs).
record:
	vhs demo/overview.tape
	vhs demo/list.tape
	vhs demo/prune.tape
	vhs demo/picker.tape
