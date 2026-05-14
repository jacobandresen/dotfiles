.PHONY: test

# Run from dev/turbovim/
test:
	cd ../.. && nvim --headless \
	  -u dev/turbovim/tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory dev/turbovim/tests/ {minimal_init = 'dev/turbovim/tests/minimal_init.lua', sequential = true}" \
	  +qa
