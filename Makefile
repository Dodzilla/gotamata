PYTHON ?= python3
SYNC_BRIDGE := tools/sync_bridge_contract.py

.PHONY: sync-bridge check-bridge deploy-rampart test

sync-bridge:
	$(PYTHON) $(SYNC_BRIDGE)

check-bridge:
	$(PYTHON) $(SYNC_BRIDGE) --check

deploy-rampart: sync-bridge
	$(PYTHON) tools/deploy_to_rampart.py

test: sync-bridge
	$(PYTHON) $(SYNC_BRIDGE) --check
