GH_USERNAME := thoth-station
BRANCH := main

all: # NOOP

prepare: # Render dev kustomization.yaml interpolating GH_USERNAME and BRANCH so you can deploy from fork
	BRANCH=$(BRANCH) GH_USERNAME=$(GH_USERNAME) envsubst < manifests/overlays/dev/phase_01/kustomization.yaml.tmpl > manifests/overlays/dev/phase_01/kustomization.yaml

deploy-phase_00: # Subscribes cluster to required operators
	kustomize build manifests/overlays/dev/phase_00 | oc apply -f -

deploy-phase_01: prepare # Applies BYON pipelines
	kustomize build manifests/overlays/dev/phase_01 | oc apply -f -

deploy: # Applies manifests on a cluster
	$(MAKE) deploy-phase_00

	@echo -n "Wait until CRDs are available"
	@until oc get kfdefs,pipelines,tasks >/dev/null 2>/dev/null; do echo -n "."; sleep 10; done
	@echo ""

	$(MAKE) deploy-phase_01

undeploy: prepare # Deletes all manifests from a cluster
	kustomize build manifests/overlays/dev/phase_00 | oc apply -f -
	kustomize build manifests/overlays/dev/phase_01 | oc delete -f -

run: # Creates and follows execution of 1 positive and 1 negative cases of validation
	tkn pipeline start byon-import-jupyterhub-image \
		--showlog \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/tcoufal/false \
		-p name="Image does not exist" \
		-p desc="This image is expected to FAIL validation"

	tkn pipeline start byon-import-jupyterhub-image \
		--showlog \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/thoth-station/s2i-minimal-py38-notebook:v0.2.2 \
		-p name="Thoth Station miminal Python 3.8" \
		-p desc="This image is expected to PASS validation"


test: # Queues various import pipelines and asserts results
	@echo -n "Queuing import pipelines..."
	@tkn pipeline start byon-import-jupyterhub-image \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/tcoufal/false \
		-p name="Image does not exist" \
		-p desc="This image is expected to FAIL validation" >/dev/null

	@tkn pipeline start byon-import-jupyterhub-image \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/thoth-station/s2i-minimal-py38-notebook:v0.2.2 \
		-p name="Thoth Station miminal Python 3.8" \
		-p desc="This image is expected to PASS validation" >/dev/null

	@tkn pipeline start byon-import-jupyterhub-image \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/thoth-station/s2i-minimal-notebook:v0.0.15 \
		-p name="Thoth Station miminal Python 3.6" \
		-p desc="This image is expected to FAIL validation" >/dev/null

	@tkn pipeline start byon-import-jupyterhub-image \
		-w name=data,volumeClaimTemplateFile=manifests/overlays/dev/pvc.yaml \
		-p url=quay.io/tcoufal/jh-minimal-test \
		-p name="Debian based miminal Python 3.8" \
		-p desc="This image is expected to PASS validation" >/dev/null
	@echo " Done"

	@echo -n "Waiting for pipelines to finish execution..."
	@while tkn pipelinerun list | grep "Running" >/dev/null; do sleep 20; echo -n "."; done
	@echo " Done"

	@echo "Results:"
	@oc get is -l app.kubernetes.io/created-by=byon -o custom-columns=NAME:.metadata.annotations.opendatahub\\.io\\/notebook-image-name,DESCRIPTION:.metadata.annotations.opendatahub\\.io\\/notebook-image-desc,PHASE:.metadata.annotations.opendatahub\\.io\\/notebook-image-phase,VISIBILITY:.metadata.annotations.opendatahub\\.io\\/notebook-image-visible,MESSAGES:.metadata.annotations.opendatahub\\.io\\/notebook-image-message

cleanup: # Cleanup from previous runs (removes all imagestreams created from `make run` and deletes all pipelinerun resources)
	oc delete is -l app.kubernetes.io/created-by=byon
	oc delete prs --all

help: # Show help message
	@awk 'BEGIN {FS = ":.*#"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[$$()% 0-9a-zA-Z_-]+:.*?#/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^#@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
