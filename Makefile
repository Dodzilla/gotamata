.PHONY: check-bridge sync-bridge

PYTHON ?= python3

check-bridge:
	$(PYTHON) tools/sync_bridge_contract.py --check

sync-bridge:
	$(PYTHON) tools/sync_bridge_contract.py
