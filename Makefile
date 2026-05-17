# mu has moved to ~/Projects/mu — build and install it from there.

.PHONY: install install-skills

install: install-skills

install-skills:
	@echo "Installing pi skills..."
	@mkdir -p $(HOME)/.pi/agent/skills
	@for skill in pi/agent/skills/*/; do \
		name=$$(basename "$$skill"); \
		mkdir -p "$(HOME)/.pi/agent/skills/$$name"; \
		cp "$$skill/SKILL.md" "$(HOME)/.pi/agent/skills/$$name/SKILL.md"; \
		echo "  ✓ $$name"; \
	done
