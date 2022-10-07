
.DEFAULT_GOAL := help

SERVICE_NAME=example-service
PLAN_NAME=example-email-plan

DOCKER_OPTS=--rm -v $(PWD):/brokerpak -w /brokerpak
CSB=ghcr.io/gsa/cloud-service-broker:v0.10.0gsa
SECURITY_USER_NAME := $(or $(SECURITY_USER_NAME), user)
SECURITY_USER_PASSWORD := $(or $(SECURITY_USER_PASSWORD), pass)

CSB_EXEC=docker exec csb-service-$(SERVICE_NAME) /bin/cloud-service-broker

CSB_SET_IDS=$(CSB_EXEC) client catalog | jq -r '.response.services[]| select(.name=="$(SERVICE_NAME)") | {serviceid: .id, planid: .plans[0].id} | to_entries | .[] | "export " + .key + "=" + (.value | @sh)'

# Wait for an instance operation to complete; append with the instance id
CSB_INSTANCE_WAIT=docker exec csb-service-$(SERVICE_NAME) ./bin/instance-wait.sh

# Wait for an binding operation to complete; append with the instance id and binding id
CSB_BINDING_WAIT=docker exec csb-service-$(SERVICE_NAME) ./bin/binding-wait.sh

# Fetch the content of a binding; append with the instance id and binding id
CSB_BINDING_FETCH=docker exec csb-service-$(SERVICE_NAME) ./bin/binding-fetch.sh

# Use the env var INSTANCE_NAME for the name of the instance to be created, or
# "instance-$USER" if it was not specified.
#
# We do this to minimize the chance of people stomping on each other when
# provisioning resources into a shared account, and to make it easy to recognize
# who resources belong to.
#
# We can also use a job ID during CI to avoid collisions from parallel
# invocations, and make it obvious which resources correspond to which CI run.
INSTANCE_NAME ?= instance-$(USER)

# Use these parameters when provisioning an instance
CLOUD_PROVISION_PARAMS="{}"

# Use these parameters when creating a binding
CLOUD_BIND_PARAMS="{}"

PREREQUISITES = docker jq
K := $(foreach prereq,$(PREREQUISITES),$(if $(shell which $(prereq)),some string,$(error "Missing prerequisite commands $(prereq)")))

check: ## Output variables for sanity-checking
	@echo CSB_EXEC: $(CSB_EXEC)
	@echo SERVICE_NAME: $(SERVICE_NAME)
	@echo PLAN_NAME: $(PLAN_NAME)
	@echo CLOUD_PROVISION_PARAMS: $(CLOUD_PROVISION_PARAMS)
	@echo CLOUD_BIND_PARAMS: $(CLOUD_BIND_PARAMS)

check-ids:
	@( \
	eval "$$( $(CSB_SET_IDS) )" ;\
	echo Service ID: $$serviceid ;\
	echo Plan ID: $$planid ;\
	)

clean: down ## Bring down the broker service if it's up, clean out the database, and remove created images
	@-rm *.brokerpak

# Origin of the subdirectory dependency solution:
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: manifest.yml $(shell find services) ## Build the brokerpak(s)
	docker run --user $(shell id -u):$(shell id -g) $(DOCKER_OPTS) $(CSB) pak build

up: .env.secrets ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser.
	docker run $(DOCKER_OPTS) \
	-p 8080:8080 \
	-e SECURITY_USER_NAME=$(SECURITY_USER_NAME) \
	-e SECURITY_USER_PASSWORD=$(SECURITY_USER_PASSWORD) \
	-e GSB_DEBUG=true \
	-e "DB_TYPE=sqlite3" \
	-e "DB_PATH=/tmp/csb-db" \
	--env-file .env.secrets \
	--name csb-service-$(SERVICE_NAME) \
	--health-cmd="wget --header=\"X-Broker-API-Version: 2.16\" --no-verbose --tries=1 --spider http://$(SECURITY_USER_NAME):$(SECURITY_USER_PASSWORD)@localhost:8080/v2/catalog || exit 1" \
	--health-interval=2s \
	--health-retries=30 \
	-d \
	$(CSB) serve
	@./bin/docker-wait.sh csb-service-$(SERVICE_NAME)
	@docker ps -l

test: .env.secrets  ## Execute the brokerpak examples against the running broker
	@echo "Running examples..."
	@( \
	set -e ;\
	eval "$$( $(CSB_SET_IDS) )" ;\
	$(CSB_EXEC) client run-examples \
	)


down: ## Bring the cloud-service-broker service down
	@-docker stop csb-service-$(SERVICE_NAME)

all: clean build up test down ## Clean and rebuild, then bring up the server, run the examples, and bring the system down
.PHONY: all clean build up test down

.env.secrets:
	$(error Copy .env.secrets-template to .env.secrets, then edit in your own values)

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
