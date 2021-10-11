# Make defaults
.ONESHELL:
.SILENT: pull-push-images create-docker-network create-kind destroy deploy-small-stack deploy-full-stack deploy-metallb deploy-metrics-server deploy-kube-prometheus-stack deploy-nginx-ingress-controller deploy-cert-manager deploy-argocd show-creds deploy-gitlab gitlab-pull-push-dind-images gitlab-create-root-personal_access_tokens
.DEFAULT_GOAL := help

SHELL := /bin/bash
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# MAKEFLAGS := --jobs=$(shell nproc)
# MAKEFLAGS += --output-sync=target

create: ## create
create: create-docker-network create-kind deploy-metrics-server deploy-metallb deploy-nginx-ingress-controller deploy-cert-manager deploy-kube-prometheus-stack
#################################################################################################################################
destroy: ## destroy
destroy:
	set +e
	cd $(ROOT_DIR)
	source tools
	delete_kind --env-file=.env
#################################################################################################################################
stop: ## stop
stop:
	set +e
	cd $(ROOT_DIR)
	source tools
	stop_cluster --env-file=.env
#################################################################################################################################
start: ## start
start:
	set +e
	cd $(ROOT_DIR)
	source tools
	start_cluster --env-file=.env
#################################################################################################################################
deploy-small-stack: # deploy-small-stack
deploy-small-stack: create
#################################################################################################################################
deploy-full-stack: # deploy-full-stack
deploy-full-stack: create deploy-argocd
#################################################################################################################################
create-docker-network: ## create-docker-network
create-docker-network:
	set -e
	cd $(ROOT_DIR)
	source tools
	create_docker_network --env-file=.env
#################################################################################################################################
create-kind: ## create-kind
create-kind:
	set -e
	cd $(ROOT_DIR)
	source tools
	create_kind --env-file=.env
#################################################################################################################################
deploy-metallb: ## deploy-metallb
deploy-metallb:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/metallb.env
	deploy_helm_chart --add-repo --pull-push-images
#################################################################################################################################
deploy-metrics-server: ## deploy-metrics-server
deploy-metrics-server:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/metrics-server.env
	deploy_helm_chart --add-repo --pull-push-images
	kubectl get --context $${KUBE_CONTEXT} --raw "/apis/metrics.k8s.io/v1beta1/nodes"|yq e -P
	kubectl get --context $${KUBE_CONTEXT} --raw "/apis/metrics.k8s.io/v1beta1/pods"|yq e -P
#################################################################################################################################
deploy-kube-prometheus-stack: ## deploy-kube-prometheus-stack
deploy-kube-prometheus-stack:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/kube-prometheus-stack.env
	deploy_helm_chart --add-repo --pull-push-images
	jq --null-input '{"apiVersion": "cert-manager.io/v1", "kind": "Issuer", "metadata":{"name": "selfsigned-issuer"}, "spec":{"selfSigned": {}} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	domains=$$(jo array[]=alertmanager.$${KIND_CLUSTER_NAME}.lan array[]=grafana.$${KIND_CLUSTER_NAME}.lan array[]=grafana.$${KIND_CLUSTER_NAME}.lan|jq '.array')
	jq --null-input --arg name "$$HELM_NAMESPACE-tls-certificate" --arg domain "$$HELM_NAMESPACE.$${KIND_CLUSTER_NAME}.lan" --argjson domains "$${domains}" '{"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata":{"name": $$name}, "spec":{"secretName": $$name, "issuerRef": {"name": "selfsigned-issuer"}, commonName: $$domain, "dnsNames": $$domains } }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
#################################################################################################################################
deploy-cert-manager: ## deploy-cert-manager
deploy-cert-manager:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/cert-manager.env
	deploy_helm_chart --add-repo --pull-push-images
#################################################################################################################################
deploy-nginx-ingress-controller: ## deploy-nginx-ingress-controller
deploy-nginx-ingress-controller:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/nginx-ingress-controller.env
	deploy_helm_chart --add-repo --pull-push-images
#################################################################################################################################
deploy-argocd: ## deploy-argocd
deploy-argocd:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/argocd.env
	deploy_helm_chart --add-repo --pull-push-images
	jq --null-input '{"apiVersion": "cert-manager.io/v1", "kind": "Issuer", "metadata":{"name": "selfsigned-issuer"}, "spec":{"selfSigned": {}} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	jq --null-input --arg name "$$HELM_NAMESPACE-tls-certificate" --arg domain "$$HELM_NAMESPACE.$${KIND_CLUSTER_NAME}.lan" '{"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata":{"name": $$name}, "spec":{"secretName": $$name, "issuerRef": {"name": "selfsigned-issuer"}, commonName: $$domain, "dnsNames": [$$domain]} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
#################################################################################################################################
deploy-gitlab: ## deploy-gitlab
deploy-gitlab:
	set -e
	cd $(ROOT_DIR)
	$(MAKE) gitlab-pull-push-dind-images
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	jq --null-input --arg namespace "$$HELM_NAMESPACE" '{"apiVersion": "v1","kind":"Namespace","metadata":{"name":$$namespace}}' | yq e -P | kubectl apply --context $$KUBE_CONTEXT -f -
	jq --null-input --arg namespace "$$HELM_NAMESPACE" '{"apiVersion":"v1","kind":"PersistentVolumeClaim","metadata":{"name":"gitlab-dind-var-lib","namespace":$$namespace},"spec":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"5Gi"}},"storageClassName":"standard","volumeMode":"Filesystem"}}' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	deploy_helm_chart --add-repo --pull-push-images --debug
	$(MAKE) gitlab-create-root-personal_access_tokens
#################################################################################################################################

gitlab-pull-push-dind-images: ## gitlab-pull-push-dind-images
gitlab-pull-push-dind-images:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	tempfile_envfile=$$(mktemp /tmp/envfile.XXXXXXXXXX)
	trap "rm -Rf $$tempfile_envfile" 0 2 3 15
	echo "DOCKER_BUILD_REPOSITORY=docker" > $$tempfile_envfile
	echo "DOCKER_BUILD_TAG=20.10.8" >> $$tempfile_envfile
	push_images --env-file=.env --env-file=helm-dependencies/gitlab.env --env-file=$$tempfile_envfile
	echo "DOCKER_BUILD_REPOSITORY=docker" > $$tempfile_envfile
	echo "DOCKER_BUILD_TAG=20.10.8-dind" >> $$tempfile_envfile
	push_images --env-file=.env --env-file=helm-dependencies/gitlab.env --env-file=$$tempfile_envfile

gitlab-create-root-personal_access_tokens: ## gitlab-create-root-personal_access_tokens
gitlab-create-root-personal_access_tokens:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	pod=$$(kubectl get pods --context $${KUBE_CONTEXT} -l app=task-runner -n $${HELM_NAMESPACE} -ojson|jq -r '.items[0].metadata.name')
	set +e; kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "token = User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token'); token.set_token('$$GITLAB_TOKEN'); token.save!"; set -e
	kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "u = User.find_by_username('root'); pp u.attributes"
#	kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "u = User.new(username: 'test_user', email: 'test@example.com', name: 'Test User', password: 'password', password_confirmation: 'password'); u.skip_confirmation!; u.save!"
# kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rake gitlab:check SANITIZE=true
# kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rake db:migrate
# eval $$(cat .env) ; eval $$(cat helm-dependencies/gitlab.env) ; set +e; kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(kubectl get pods --context $${KUBE_CONTEXT} -l app=task-runner -n $${HELM_NAMESPACE} -ojson|jq -r '.items[0].metadata.name') -c task-runner -- gitlab-rails runner "token = User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token'); token.set_token('$$GITLAB_TOKEN'); token.save!"; set -e

import-argocd-crt: ## import-argocd-crt
import-argocd-crt:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/argocd.env
	tempfile=$$(mktemp /tmp/crt.XXXXXXXXXX)
	trap "rm -Rf $$tempfile" 0 2 3 15
	file=argocd.$${KIND_CLUSTER_NAME}.lan.crt
	key=tls.crt
	kubectl get secrets/argocd-tls-certificate --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d >> $$tempfile
	key=ca.crt
	kubectl get secrets/argocd-tls-certificate --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d >> $$tempfile
	sudo cp $$tempfile /usr/local/share/ca-certificates/$${file}
	sudo update-ca-certificates

import-gitlab-crt: ## import-gitlab-crt
import-gitlab-crt:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	tempfile=$$(mktemp /tmp/crt.XXXXXXXXXX)
	trap "rm -Rf $$tempfile" 0 2 3 15
	key=gitlab.$${KIND_CLUSTER_NAME}.lan.crt
	file=gitlab.$${KIND_CLUSTER_NAME}.lan.crt
	kubectl get secrets/gitlab-wildcard-tls-chain --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d > $$tempfile
	sudo cp $$tempfile /usr/local/share/ca-certificates/$${file}
	sudo update-ca-certificates

# https://superuser.com/questions/437330/how-do-you-add-a-certificate-authority-ca-to-ubuntu
install-cert-tools: ## install-cert-tools
install-cert-tools:
	set -e
	packages="p11-kit libnss3"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ] && packages_list="$$packages_list $$package"; done
	echo $$packages_list; \
	if ! [ -z "$$packages_list" ]; then \
		sudo /bin/bash -c "apt update && apt-get --no-install-recommends install -y $$packages_list"; \
	fi
	find / -type f ! -path '/snap/*' -name "libnssckbi.so" 2>/dev/null | while read line; do \
		sudo mv $$line $${line}.bak; \
		sudo ln -s /usr/lib/$$(uname -m)-linux-gnu/pkcs11/p11-kit-trust.so $$line; \
	done

show-creds: ## show-creds
show-creds:
	set -e
	cd $(ROOT_DIR)
	eval $$(cat .env)
###############
	eval $$(cat helm-dependencies/kube-prometheus-stack.env)

	app=alertmanager
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app $$app --arg url "http://$${url}" '{"app": $$app, "url": $$url}' | yq e -P

	app=prometheus
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app $$app --arg url "http://$${url}" '{"app": $$app, "url": $$url}' | yq e -P

	app=grafana
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app $$app --arg user admin --arg password $$GRAFANA_ADMIN_PASSWORD --arg url "http://$${url}" '{"app": $$app, "url": $$url, "creds":{"user": $$user, "password":$$password}}' | yq e -P
#############################################################################
	echo ---
	jq --null-input --arg app metallb --arg secret $${METALLB_SPEAKER_SECRET_VALUE} '{"app": $$app, "secret": $$secret}' | yq e -P
#############################################################################	
	eval $$(cat helm-dependencies/argocd.env)

	app=argocd-server
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app argocd --arg user admin --arg password $$ARGOCD_SERVER_ADMIN_PASSWORD --arg url "http://$${url}" '{"app": $$app, "url": $$url, "creds":{"user": $$user, "password":$$password}}' | yq e -P
#############################################################################
	eval $$(cat helm-dependencies/gitlab.env)

	app=webservice-default
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	gitlab_password=$$(kubectl get secret $${HELM_RELEASE}-gitlab-initial-root-password --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.data.password}' | base64 --decode ; echo)
	echo ---
	jq --null-input --arg app gitlab --arg user root --arg password $$gitlab_password --arg url "http://$${url}" '{"app": $$app, "url": $$url, "creds":{"user": $$user, "password":$$password}}' | yq e -P
###################################################################################################################################################################################
###################################################################################################################################################################################
BIN_DIR := ~/bin

install: ## install
install: install-docker install-kubectl prepare-env install-packages install-kind install-helm install-yq install-lens install-kubectx install-kubens install-dnsmasq

install-kubectl: ## install-kubectl
install-kubectl:
	if ! [ -f /usr/share/keyrings/kubernetes-archive-keyring.gpg ]; then \
		curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg ; \
	fi; \
	if [[ ! -f /etc/apt/sources.list.d/kubernetes.list ]] || [[ ! $$(grep -Po "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" /etc/apt/sources.list.d/kubernetes.list) ]] ; then \
		echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
	fi; \
	packages="kubectl"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ] && packages_list="$$packages_list $$package"; done
	if ! [ -z "$$packages_list" ]; then \
		sudo /bin/bash -c "apt update && apt-get --no-install-recommends install -y $$packages_list"; \
	fi; \

install-docker: ## install-docker
install-docker:
	packages="apt-transport-https ca-certificates curl gnupg lsb-release"; \
	packages_list=''; \
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ] && packages_list="$$packages_list $$package"; done
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
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ] && packages_list="$$packages_list $$package"; done
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
	for package in $$packages; do [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ] && packages_list="$$packages_list $$package"; done
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
	if [ -z "`dpkg -l | grep -P "ii\s+$$package(?:[\s+|:])" || :`" ]; then \
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

	sudo systemctl disable --now systemd-resolved
	sudo systemctl restart dnsmasq

###################################################################################################################################################################################
###################################################################################################################################################################################

help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'
