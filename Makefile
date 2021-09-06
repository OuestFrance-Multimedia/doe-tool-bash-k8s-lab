include .env

# KIND_CONFIG_FILE := /tmp/kind-${KIND_CLUSTER_NAME}-config.yml
KIND_CONFIG_FILE := kind-config.yaml
METALLB_CONFIG_FILE := /tmp/metallb-${KIND_CLUSTER_NAME}-config.yml
METRICS_SERVER_CONFIG_FILE := /tmp/metrics-server-${KIND_CLUSTER_NAME}-config.yml
PROMETHEUS_CONFIG_FILE := /tmp/prometheus-${KIND_CLUSTER_NAME}-config.yml
KUBE_CONTEXT := kind-${KIND_CLUSTER_NAME}
NETWORK_CIDR := ${NETWORK_PREFIX}.0.0/16
NETWORK_GATEWAY := ${NETWORK_PREFIX}.0.1
METALLB_DEFAULT_ADDRESS_POOL=${NETWORK_PREFIX}.255.1-${NETWORK_PREFIX}.255.254


# Make defaults
.ONESHELL:
.SILENT: pull-push-images
.DEFAULT_GOAL := help

SHELL := /bin/bash

create: ## create
create: create-docker-network create-kind deploy-metallb deploy-metrics-server deploy-monitoring

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
#	$(file > ${KIND_CONFIG_FILE},${KIND_CONFIG_FILE_CONTENT})
	export KIND_EXPERIMENTAL_DOCKER_NETWORK=${KIND_CLUSTER_NAME}
	kind create cluster \
		--name ${KIND_CLUSTER_NAME} \
		--config ${KIND_CONFIG_FILE} \
		--image ${KIND_CLUSTER_IMAGE}
# -v 6

# https://artifacthub.io/packages/helm/bitnami/metallb
METALLB_REPO := bitnami
METALLB_CHART := metallb
METALLB_VERSION := 2.5.4 # 2.3.7 # helm search repo bitnami/metallb --output yaml| yq e '.[0].version' -
#################################################################################################################################
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
#################################################################################################################################
deploy-metallb: ## deploy-metallb
deploy-metallb:
	set -e
	$(file > ${METALLB_CONFIG_FILE},$(METALLB_CONFIG_FILE_CONTENT))
	helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
# kubectl get all -n metallb -oyaml|grep -Po "image: \K(\S+)"|sort|uniq
	for image in $$(helm template --kube-context $(KUBE_CONTEXT) --values ${METALLB_CONFIG_FILE} --version ${METALLB_VERSION} ${METALLB_REPO}/${METALLB_CHART}|grep -Po 'image: "\K([^"]+)'|sort -u); do \
		docker pull $$image; \
		kind load docker-image $$image --name ${KIND_CLUSTER_NAME}
	done
	helm upgrade \
		--kube-context $(KUBE_CONTEXT) \
		--install \
		--wait \
		--values ${METALLB_CONFIG_FILE} \
		--namespace metallb \
		--create-namespace \
		--version ${METALLB_VERSION} \
		${METALLB_CHART} ${METALLB_REPO}/${METALLB_CHART}

# https://artifacthub.io/packages/helm/bitnami/metrics-server
METRICS_SERVER_REPO := bitnami
METRICS_SERVER_CHART := metrics-server
METRICS_SERVER_VERSION := 5.8.9
#################################################################################################################################
define METRICS_SERVER_CONFIG_FILE_CONTENT :=
---
apiService:
  create: true
extraArgs:
  kubelet-insecure-tls: true
  kubelet-preferred-address-types: InternalIP
endef
#################################################################################################################################
deploy-metrics-server: ## deploy-metrics-server
deploy-metrics-server:
	set -e
	$(file > ${METRICS_SERVER_CONFIG_FILE},$(METRICS_SERVER_CONFIG_FILE_CONTENT))
	helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
	for image in $$(helm template --kube-context $(KUBE_CONTEXT) --values ${METRICS_SERVER_CONFIG_FILE} --version ${METRICS_SERVER_VERSION} ${METRICS_SERVER_REPO}/${METRICS_SERVER_CHART}|grep -Po 'image: "\K([^"]+)'|sort -u); do \
		docker pull $$image; \
		kind load docker-image $$image --name ${KIND_CLUSTER_NAME}
	done
	helm upgrade \
		--kube-context $(KUBE_CONTEXT) \
		--install \
		--wait \
		--values ${METRICS_SERVER_CONFIG_FILE} \
		--namespace monitoring \
		--create-namespace \
		--version ${METRICS_SERVER_VERSION} \
		${METRICS_SERVER_CHART} ${METRICS_SERVER_REPO}/${METRICS_SERVER_CHART}
	kubectl get --context $(KUBE_CONTEXT) --raw "/apis/metrics.k8s.io/v1beta1/nodes"|yq e -P
	kubectl get --context $(KUBE_CONTEXT) --raw "/apis/metrics.k8s.io/v1beta1/pods"|yq e -P

# https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
PROMETHEUS_REPO := prometheus-community
PROMETHEUS_CHART := kube-prometheus-stack
PROMETHEUS_VERSION := 18.0.3 # helm search repo prometheus-community/kube-prometheus-stack --output yaml| yq e '.[0].version' -
#################################################################################################################################
define PROMETHEUS_CONFIG_FILE_CONTENT :=
---
grafana:
  enabled: false
endef
#################################################################################################################################
deploy-monitoring: ## deploy-monitoring:
deploy-monitoring:
	set -e
	$(file > ${PROMETHEUS_CONFIG_FILE},$(PROMETHEUS_CONFIG_FILE_CONTENT))
	helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts
	for image in $$(helm template --kube-context $(KUBE_CONTEXT) --values ${PROMETHEUS_CONFIG_FILE} --version ${PROMETHEUS_VERSION} ${PROMETHEUS_REPO}/${PROMETHEUS_CHART}|grep -Po 'image: "\K([^"]+)'|sort -u); do \
		docker pull $$image; \
		kind load docker-image $$image --name ${KIND_CLUSTER_NAME}
	done
	helm upgrade \
		--kube-context $(KUBE_CONTEXT) \
		--install \
		--wait \
		--values ${PROMETHEUS_CONFIG_FILE} \
		--namespace monitoring \
		--create-namespace \
		--version ${PROMETHEUS_VERSION} \
		${PROMETHEUS_CHART} ${PROMETHEUS_REPO}/${PROMETHEUS_CHART}

destroy: ## destroy
destroy:
	set +e
	kind delete cluster --name ${KIND_CLUSTER_NAME}
	docker network rm ${KIND_CLUSTER_NAME}

###################################################################################################################################################################################
###################################################################################################################################################################################
BIN_DIR := ~/bin

install: ## install
install: install-docker prepare-env install-packages install-kind install-helm install-yq install-lens install-kubectx install-kubens install-dnsmasq

install-docker: ## install-docker
install-docker:
	packages="apt-transport-https ca-certificates curl gnupg lsb-release"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package\s+" || :`" ] && packages_list="$$packages_list $$package"; done
	if ! [ -z "$$packages_list" ]; then \
		sudo /bin/bash -c "apt update && apt-get --no-install-recommends install -y $$packages_list"; \
	fi; \
	if ! [ -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then \
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg ; \
	fi; \
	architecture="" ; \
	case $$(uname -m) in \
		x86_64) architecture="amd64" ;; \
		amd64) architecture="amd64" ;; \
		arm64) architecture="arm64" ;; \
		aarch64) architecture="arm64" ;; \
		arm)	dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;; \
	esac ; \
	if [[ ! -f /etc/apt/sources.list.d/docker.list ]] || [[ ! $$(grep -Po "deb \[arch=$$architecture signed-by=/usr/share/keyrings/docker-archive-keyring.gpg\] https://download.docker.com/linux/ubuntu $$(lsb_release -cs) stable" /etc/apt/sources.list.d/docker.list) ]] ; then \
		echo "deb [arch=$$architecture signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	fi; \
	packages="docker-ce docker-ce-cli containerd.io"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package\s+" || :`" ] && packages_list="$$packages_list $$package"; done
	if ! [ -z "$$packages_list" ]; then \
		sudo /bin/bash -c "apt update && apt-get --no-install-recommends install -y $$packages_list"; \
	fi; \
	if [[ -z $$(grep -Po "^docker:" /etc/group) ]] ; then \
		sudo groupadd docker; \
	fi; \
	if [[ -z $$(awk -F':' '/docker/{print $$4}' /etc/group | grep -Po "(^$${USER}$$|,$${USER}$$|^$${USER},)") ]] ; then \
		sudo usermod -aG docker $$USER; \
		killall -KILL -u $$USER; \
	fi; \

prepare-env: ## prepare-env
prepare-env:
	mkdir -p $(BIN_DIR)
	source ~/.profile

install-kind: ## install-kind
install-kind:
	set -e
	arch="" ; \
	case $$(uname -m) in \
		x86_64) arch="amd64" ;; \
		amd64) arch="amd64" ;; \
		arm64) arch="arm64" ;; \
		aarch64) arch="arm64" ;; \
		arm)	dpkg --print-architecture | grep -q "arm64" && arch="arm64" ;; \
	esac ; \
	repo=kubernetes-sigs/kind; \
	word=kind; \
	content_type=$${content_type:-application}; \
	os=$${os:-linux}; \
	word=$${word:-$$(basename $$repo)}; \
	releases=$$(curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--url https://api.github.com/repos/$$repo/releases); \
	release=$$(echo "$$releases" | jq --arg os $${os,,} --arg arch $${arch,,} --arg content_type $${content_type,,} --arg word $${word,,} 'first( .[] | select(.prerelease == false) | .assets[] | select(.name|ascii_downcase|contains($$os)) | select(.name|ascii_downcase|contains($$arch)) | select(.content_type|ascii_downcase|contains($$content_type)) | select(.name|ascii_downcase|contains($$word)) )'); \
	url=$$(echo "$${release}" | jq -r '.browser_download_url'); \
	file="/tmp/$$(basename $$url)"; \
	echo $$file; \
	curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--location \
		--output $$file \
		--url $$url; \
	chmod +x $$file
	mv $$file $(BIN_DIR)/kind

install-packages: ## install-packages
install-packages:
	packages="openssl kubectl jq jo dnsutils iputils-ping netcat procps curl mariadb-client"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package\s+" || :`" ] && packages_list="$$packages_list $$package"; done
	if ! [ -z "$$packages_list" ]; then \
		sudo /bin/bash -c "apt update && apt-get --no-install-recommends install -y $$packages_list"; \
	fi; \

install-helm: ## install-helm
install-helm:
	wget -q -O - https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | HELM_INSTALL_DIR=$(BIN_DIR) USE_SUDO="false" bash

install-yq: ## install-yq
install-yq:
	sudo snap install yq

install-lens: ## install-lens
install-lens:
	sudo snap install kontena-lens --classic

install-kubectx: ## install-kubectx
install-kubectx:
	set -e
	repo=ahmetb/kubectx; \
	word=kubectx; \
	arch=$$(uname -m); \
	content_type=$${content_type:-application}; \
	os=$${os:-linux}; \
	word=$${word:-$$(basename $$repo)}; \
	releases=$$(curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--url https://api.github.com/repos/$$repo/releases); \
	release=$$(echo "$$releases" | jq --arg os $${os,,} --arg arch $${arch,,} --arg content_type $${content_type,,} --arg word $${word,,} 'first( .[] | select(.prerelease == false) | .assets[] | select(.name|ascii_downcase|contains($$os)) | select(.name|ascii_downcase|contains($$arch)) | select(.content_type|ascii_downcase|contains($$content_type)) | select(.name|ascii_downcase|contains($$word)) )'); \
	url=$$(echo "$${release}" | jq -r '.browser_download_url'); \
	file="/tmp/$$(basename $$url)"; \
	echo $$url; \
	echo $$file; \
	curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--location \
		--output $$file \
		--url $$url; \
	tempdir=$$(mktemp --directory $(BIN_DIR)/$${word}.XXXXXXXXXX); \
	trap "rm -Rf $$tempdir" 0 2 3 15; \
	tar -xzf $$file -C $$tempdir; \
	mv $$tempdir/$${word} $(BIN_DIR)/$${word}; \
	rm -Rf $$tempdir; \
	chmod +x $(BIN_DIR)/$${word}

install-kubens: ## install-kubens
install-kubens:
	set -e
	repo=ahmetb/kubectx; \
	word=kubens; \
	arch=$$(uname -m); \
	content_type=$${content_type:-application}; \
	os=$${os:-linux}; \
	word=$${word:-$$(basename $$repo)}; \
	releases=$$(curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--url https://api.github.com/repos/$$repo/releases); \
	release=$$(echo "$$releases" | jq --arg os $${os,,} --arg arch $${arch,,} --arg content_type $${content_type,,} --arg word $${word,,} 'first( .[] | select(.prerelease == false) | .assets[] | select(.name|ascii_downcase|contains($$os)) | select(.name|ascii_downcase|contains($$arch)) | select(.content_type|ascii_downcase|contains($$content_type)) | select(.name|ascii_downcase|contains($$word)) )'); \
	url=$$(echo "$${release}" | jq -r '.browser_download_url'); \
	file="/tmp/$$(basename $$url)"; \
	echo $$url; \
	echo $$file; \
	curl \
		$${GITHUB_PERSONAL_ACCESS_TOKEN:+--header 'Authorization: bearer '$$GITHUB_PERSONAL_ACCESS_TOKEN} \
		--silent \
		--location \
		--output $$file \
		--url $$url; \
	tempdir=$$(mktemp --directory $(BIN_DIR)/$${word}.XXXXXXXXXX); \
	trap "rm -Rf $$tempdir" 0 2 3 15; \
	tar -xzf $$file -C $$tempdir; \
	mv $$tempdir/$${word} $(BIN_DIR)/$${word}; \
	rm -Rf $$tempdir; \
	chmod +x $(BIN_DIR)/$${word}

install-dnsmasq: ## install-dnsmasq
install-dnsmasq:
	set -e
	if [ -z "$$(find /var/cache/apt/pkgcache.bin -mmin -1440)" ]; then \
		sudo apt-get update; \
	fi

	package='dnsmasq'; \
	if [ -z "`dpkg -l | grep -P "ii\s+$$package\s+" || :`" ]; then \
		sudo apt install -y $$package; \
	fi

config-dnsmasq: ## config-dnsmasq
config-dnsmasq:
	sudo chattr -i /etc/resolv.conf
	sudo rm -rf /etc/resolv.conf
	sudo /bin/bash -c "echo 'nameserver 127.0.0.1' >> /etc/resolv.conf"
	for ns in $$(nmcli dev show|grep -Po "IP4.DNS[^:]+:\s+\K(\d+\.\d+\.\d+\.\d+)"|sort -u); do sudo /bin/bash -c "echo 'nameserver $$ns' >> /etc/resolv.conf"; done
	sudo /bin/bash -c "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"
	sudo chattr +i /etc/resolv.conf

	sudo /bin/bash -c "echo 'port=53' > /etc/dnsmasq.conf"
	sudo /bin/bash -c "echo 'listen-address=127.0.0.1' >> /etc/dnsmasq.conf"

	sudo cp dnsmasq*.conf /etc/dnsmasq.d

	sudo systemctl disable --now systemd-resolved
	sudo systemctl restart dnsmasq

###################################################################################################################################################################################
###################################################################################################################################################################################

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'
