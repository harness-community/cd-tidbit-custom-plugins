.PHONY: validate cleanup port-forward port-forward-dev port-forward-prod build-local run-local

validate:
	./scripts/validate-setup.sh

cleanup:
	./scripts/cleanup.sh

# Foreground port-forward to both Dev (8080) and Prod (8081). Auto-reconnects
# when pods rotate. Ctrl-C cleans both up.
port-forward:
	./scripts/port-forward.sh

port-forward-dev:
	kubectl port-forward svc/custom-plugins-demo 8080:80 -n web-dev

port-forward-prod:
	kubectl port-forward svc/custom-plugins-demo 8081:80 -n web-prod

build-local:
	docker build -t custom-plugins:local app/

run-local:
	docker run --rm -p 8080:8080 custom-plugins:local
