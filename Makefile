include .env

KIND_CONFIG_FILE := /tmp/kind-${KIND_CLUSTER_NAME}-config.yml
METALLB_CONFIG_FILE := /tmp/metallb-${KIND_CLUSTER_NAME}-config.yml
METRICS_SERVER_CONFIG_FILE := /tmp/metrics-server-${KIND_CLUSTER_NAME}-config.yml
KUBE_CONTEXT := kind-${KIND_CLUSTER_NAME}
NETWORK_CIDR := ${NETWORK_PREFIX}.0.0/16
NETWORK_GATEWAY := ${NETWORK_PREFIX}.0.1
METALLB_DEFAULT_ADDRESS_POOL=${NETWORK_PREFIX}.255.1-${NETWORK_PREFIX}.255.254

define KIND_CONFIG_FILE_CONTENT :=
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration # InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "role=api"
endef

define METALLB_CONFIG_FILE_CONTENT :=
---
## configInline specifies MetalLB's configuration directly, in yaml format. When configInline is used, Helm manages MetalLB's
## configuration ConfigMap as part of the release, and existingConfigMap is ignored.
## Refer to https://metallb.universe.tf/configuration/ for available options.
configInline:
  address-pools:
  - name: default
    protocol: layer2
    addresses:
    - $(METALLB_DEFAULT_ADDRESS_POOL)
speaker:
  secretValue: ${METALLB_SPEAKER_SECRET_VALUE}
endef

define METRICS_SERVER_CONFIG_FILE_CONTENT :=
---
apiService:
  create: true
extraArgs:
  kubelet-insecure-tls: true
  kubelet-preferred-address-types: InternalIP
endef

# Make defaults
.ONESHELL:
.SILENT: pull-push-images
.DEFAULT_GOAL := help

SHELL := /bin/bash

create: ## create
create: create-docker-network create-kind create-metallb create-metrics-server

# KIND_EXPERIMENTAL_DOCKER_NETWORK
create-docker-network: ## create-docker-network
create-docker-network:
	set -e
	if [[ -z "$$(docker network ls --filter "name=^${KIND_CLUSTER_NAME}$$" -q)" ]]; then \
		docker network create \
			--scope local \
			--driver bridge \
			--subnet $(NETWORK_CIDR) \
			--gateway $(NETWORK_GATEWAY) \
			$(KIND_CLUSTER_NAME); \
	fi; \

# # https://kind.sigs.k8s.io/docs/user/configuration/
create-kind: ## create-kind
create-kind:
	set -e
	$(file > ${KIND_CONFIG_FILE},${KIND_CONFIG_FILE_CONTENT})
	export KIND_EXPERIMENTAL_DOCKER_NETWORK=${KIND_CLUSTER_NAME}
	kind create cluster \
		--name ${KIND_CLUSTER_NAME} \
		--config ${KIND_CONFIG_FILE} \
		--image ${KIND_CLUSTER_IMAGE}
# -v 6

create-metallb: ## apply-metallb
create-metallb:
	set -e
	$(file > ${METALLB_CONFIG_FILE},$(METALLB_CONFIG_FILE_CONTENT))
	helm repo add --force-update metallb https://charts.bitnami.com/bitnami
# kubectl get all -n metallb -oyaml|grep -Po "image: \K(\S+)"|sort|uniq
	docker pull docker.io/bitnami/metallb-controller:0.9.6-debian-10-r52
	docker pull docker.io/bitnami/metallb-speaker:0.9.6-debian-10-r54
	kind load docker-image docker.io/bitnami/metallb-controller:0.9.6-debian-10-r52 --name ${KIND_CLUSTER_NAME}
	kind load docker-image docker.io/bitnami/metallb-speaker:0.9.6-debian-10-r54 --name ${KIND_CLUSTER_NAME}
	helm upgrade \
		--kube-context $(KUBE_CONTEXT) \
		--install \
		--wait \
		--values ${METALLB_CONFIG_FILE} \
		--namespace metallb \
		--create-namespace \
		--version 2.3.7 \
		metallb metallb/metallb

create-metrics-server: ## create-metrics-server
create-metrics-server:
	set -e
	$(file > ${METRICS_SERVER_CONFIG_FILE},$(METRICS_SERVER_CONFIG_FILE_CONTENT))
	helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
	docker pull docker.io/bitnami/metrics-server:0.5.0-debian-10-r0
	kind load docker-image docker.io/bitnami/metrics-server:0.5.0-debian-10-r0 --name ${KIND_CLUSTER_NAME}
	helm upgrade \
		--kube-context $(KUBE_CONTEXT) \
		--install \
		--wait \
		--values ${METRICS_SERVER_CONFIG_FILE} \
		--namespace monitoring \
		--create-namespace \
		--version 5.8.9 \
		metrics-server bitnami/metrics-server

destroy: ## destroy
destroy:
	set +e
	kind delete cluster --name ${KIND_CLUSTER_NAME}
	docker network rm ${KIND_CLUSTER_NAME}

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'
