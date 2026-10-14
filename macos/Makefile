PYTHON ?= python3
.PHONY: test app doctor probe
test:
	$(PYTHON) -m unittest discover -s tests -v
app:
	$(PYTHON) build_app.py
doctor:
	$(PYTHON) proton4mac.py doctor
probe:
	$(PYTHON) tests/build_probe.py --output build/probe
