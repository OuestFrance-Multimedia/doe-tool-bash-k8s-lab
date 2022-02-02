# Make defaults
.ONESHELL:
.SILENT: pull-push-images create-docker-network create-kind destroy deploy-small-stack deploy-full-stack deploy-metallb deploy-metrics-server deploy-kube-prometheus-stack deploy-nginx-ingress-controller deploy-cert-manager deploy-argocd show-creds deploy-gitlab gitlab-pull-push-dind-images gitlab-create-root-personal_access_tokens import-kube-prometheus-stack-crt import-argocd-crt import-gitlab-crt config-etc-hosts
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
install-variant-aroma: ## docker-network + kind + metallb + nginx-ingress-ctrl + cert-manager + metrics-server + kube-prometheus-stack + argocd + gitlab
install-variant-aroma: install-variant-full deploy-kube-prometheus-stack deploy-argocd deploy-gitlab import-kube-prometheus-stack-crt import-argocd-crt import-gitlab-crt
#################################################################################################################################
install-variant-super: ## docker-network + kind + metallb + nginx-ingress-ctrl + cert-manager + metrics-server + kube-prometheus-stack + argocd
install-variant-super: install-variant-full deploy-kube-prometheus-stack deploy-argocd import-kube-prometheus-stack-crt import-argocd-crt
#################################################################################################################################
install-variant-stock: ## docker-network + kind + metallb + nginx-ingress-ctrl + cert-manager + metrics-server + kube-prometheus-stack
install-variant-stock: install-variant-full deploy-kube-prometheus-stack import-kube-prometheus-stack-crt
#################################################################################################################################
install-variant-full: ## docker-network + kind + metallb + nginx-ingress-ctrl + cert-manager + metrics-server
install-variant-full: install-variant-mini deploy-metrics-server
#################################################################################################################################
install-variant-mini: ## docker-network + kind + metallb + nginx-ingress-ctrl + cert-manager
install-variant-mini: install-variant-micro deploy-cert-manager
#################################################################################################################################
install-variant-micro: ## docker-network + kind + metallb + nginx-ingress-ctrl
install-variant-micro: install-variant-nano deploy-nginx-ingress-controller
#################################################################################################################################
install-variant-nano: ## docker-network + kind + metallb
install-variant-nano: install-variant-pico deploy-metallb
#################################################################################################################################
install-variant-pico: ## docker-network + kind
install-variant-pico: create-docker-network create-kind

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
	deploy_helm_chart --add-repo --pull-push-images --debug
#################################################################################################################################
deploy-metrics-server: ## deploy-metrics-server
deploy-metrics-server:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/metrics-server.env
	deploy_helm_chart --add-repo --pull-push-images --debug
	kubectl get --context $${KUBE_CONTEXT} --raw "/apis/metrics.k8s.io/v1beta1/nodes"|yq e -P
	kubectl get --context $${KUBE_CONTEXT} --raw "/apis/metrics.k8s.io/v1beta1/pods"|yq e -P
#################################################################################################################################
deploy-kube-prometheus-stack: ## deploy-kube-prometheus-stack
deploy-kube-prometheus-stack:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/kube-prometheus-stack.env
	deploy_helm_chart --add-repo --pull-push-images --debug
	jq --null-input '{"apiVersion": "cert-manager.io/v1", "kind": "Issuer", "metadata":{"name": "selfsigned-issuer"}, "spec":{"selfSigned": {}} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	domains=$$(jo array[]=alertmanager.$${KIND_CLUSTER_NAME}.lan array[]=grafana.$${KIND_CLUSTER_NAME}.lan array[]=prometheus.$${KIND_CLUSTER_NAME}.lan|jq '.array')
	jq --null-input --arg name "monitoring-tls-certificate" --arg domain "$${HELM_NAMESPACE}.$${KIND_CLUSTER_NAME}.lan" --argjson domains "$${domains}" '{"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata":{"name": $$name}, "spec":{"secretName": $$name, "issuerRef": {"name": "selfsigned-issuer"}, commonName: $$domain, "dnsNames": $$domains } }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
#################################################################################################################################
deploy-promtail: ## deploy-promtail
deploy-promtail:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/grafana_promtail.env
	deploy_helm_chart --add-repo --pull-push-images --debug

#################################################################################################################################
# https://github.com/grafana/helm-charts/tree/main/charts

# https://artifacthub.io/packages/helm/grafana/loki-canary
# https://artifacthub.io/packages/helm/grafana/loki-distributed
# https://artifacthub.io/packages/helm/grafana/loki-simple-scalable
# https://artifacthub.io/packages/helm/grafana/loki-stack
# https://artifacthub.io/packages/helm/grafana/loki


deploy-loki-stack: ## deploy-loki-stack
deploy-loki-stack:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/grafana_loki-stack.env
	deploy_helm_chart --add-repo --pull-push-images --debug
#################################################################################################################################
deploy-cert-manager: ## deploy-cert-manager
deploy-cert-manager:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/cert-manager.env
	deploy_helm_chart --add-repo --pull-push-images --debug
	jq --null-input '{"apiVersion":"cert-manager.io/v1","kind":"ClusterIssuer","metadata":{"name":"selfsigned-cluster-issuer"},"spec":{"selfSigned":{}}}' | yq e -P | kubectl apply --context $$KUBE_CONTEXT -f -
#################################################################################################################################
deploy-nginx-ingress-controller: ## deploy-nginx-ingress-controller
deploy-nginx-ingress-controller:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/ingress-nginx.env
	deploy_helm_chart --add-repo --pull-push-images --debug
#################################################################################################################################
deploy-argocd: ## deploy-argocd
deploy-argocd:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/argocd.env
	deploy_helm_chart --add-repo --pull-push-images --debug
	jq --null-input '{"apiVersion": "cert-manager.io/v1", "kind": "Issuer", "metadata":{"name": "selfsigned-issuer"}, "spec":{"selfSigned": {}} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	jq --null-input --arg name "$$HELM_NAMESPACE-tls-certificate" --arg domain "$${HELM_NAMESPACE}.$${KIND_CLUSTER_NAME}.lan" '{"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata":{"name": $$name}, "spec":{"secretName": $$name, "issuerRef": {"name": "selfsigned-issuer"}, commonName: $$domain, "dnsNames": [$$domain]} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
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
	jq --null-input '{"apiVersion": "cert-manager.io/v1", "kind": "Issuer", "metadata":{"name": "selfsigned-issuer"}, "spec":{"selfSigned": {}} }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
	domains=$$(jo array[]=gitlab.$${KIND_CLUSTER_NAME}.lan array[]=minio.$${KIND_CLUSTER_NAME}.lan array[]=registry.$${KIND_CLUSTER_NAME}.lan|jq '.array')
	jq --null-input --arg name "gitlab-tls-certificate" --arg domain "$${HELM_NAMESPACE}.$${KIND_CLUSTER_NAME}.lan" --argjson domains "$${domains}" '{"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata":{"name": $$name}, "spec":{"secretName": $$name, "issuerRef": {"name": "selfsigned-issuer"}, commonName: $$domain, "dnsNames": $$domains } }' | yq e -P | kubectl apply --context $$KUBE_CONTEXT --namespace "$$HELM_NAMESPACE" -f -
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
#################################################################################################################################
gitlab-create-root-personal_access_tokens: ## gitlab-create-root-personal_access_tokens
gitlab-create-root-personal_access_tokens:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	pod=$$(kubectl get pods --context $${KUBE_CONTEXT} -l app=task-runner -n $${HELM_NAMESPACE} -ojson|jq -r '.items[0].metadata.name')
	set +e; kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "group = Group.find_by_name('GitLab Instance'); project = Project.find_by_full_path(group.path + '/Monitoring'); user = User.find_by_username('root'); ProjectDestroyWorker.perform_async(project.id, user.id, {})"; set -e
#	kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "project = Project.find(1); user = User.find_by_username('root'); ProjectDestroyWorker.perform_async(project.id, user.id, {})"
	set +e; kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "token = User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token'); token.set_token('$$GITLAB_TOKEN'); token.save!"; set -e
	kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "u = User.find_by_username('root'); pp u.attributes"
#	kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rails runner "u = User.new(username: 'test_user', email: 'test@example.com', name: 'Test User', password: 'password', password_confirmation: 'password'); u.skip_confirmation!; u.save!"
# kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rake gitlab:check SANITIZE=true
# kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(echo $$pod) -c task-runner -- gitlab-rake db:migrate
# eval $$(cat .env) ; eval $$(cat helm-dependencies/gitlab.env) ; set +e; kubectl exec --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -it $$(kubectl get pods --context $${KUBE_CONTEXT} -l app=task-runner -n $${HELM_NAMESPACE} -ojson|jq -r '.items[0].metadata.name') -c task-runner -- gitlab-rails runner "token = User.find_by_username('root').personal_access_tokens.create(scopes: [:api], name: 'Automation token'); token.set_token('$$GITLAB_TOKEN'); token.save!"; set -e
#################################################################################################################################
import-kube-prometheus-stack-crt: ## import-kube-prometheus-stack-crt
import-kube-prometheus-stack-crt:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/kube-prometheus-stack.env
	tempfile=$$(mktemp /tmp/crt.XXXXXXXXXX)
	trap "rm -Rf $$tempfile" 0 2 3 15
	file=monitoring.$${KIND_CLUSTER_NAME}.lan.crt
	key=ca.crt
	kubectl get secrets/monitoring-tls-certificate --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d >> $$tempfile
	nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); until [[ $$nb -eq 0 ]]; do sleep 1; certutil -d sql:$$HOME/.pki/nssdb -D -n "$${file}" && nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); done
	certutil -d sql:$$HOME/.pki/nssdb -A -t "CT,c,c" -n "$${file}" -i $$tempfile
	certutil -d sql:$$HOME/.pki/nssdb -L
	sudo cp $$tempfile /usr/local/share/ca-certificates/$${file}
	sudo update-ca-certificates
#################################################################################################################################
import-argocd-crt: ## import-argocd-crt
import-argocd-crt:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/argocd.env
	tempfile=$$(mktemp /tmp/crt.XXXXXXXXXX)
	trap "rm -Rf $$tempfile" 0 2 3 15
	file=argocd.$${KIND_CLUSTER_NAME}.lan.crt
	key=ca.crt
	kubectl get secrets/argocd-tls-certificate --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d >> $$tempfile
	nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); until [[ $$nb -eq 0 ]]; do sleep 1; certutil -d sql:$$HOME/.pki/nssdb -D -n "$${file}" && nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); done
	certutil -d sql:$$HOME/.pki/nssdb -A -t "CT,c,c" -n "$${file}" -i $$tempfile
	certutil -d sql:$$HOME/.pki/nssdb -L
	sudo cp $$tempfile /usr/local/share/ca-certificates/$${file}
	sudo update-ca-certificates
#################################################################################################################################
import-gitlab-crt: ## import-gitlab-crt
import-gitlab-crt:
	set -e
	cd $(ROOT_DIR)
	source tools
	eval_env_files .env helm-dependencies/gitlab.env
	tempfile=$$(mktemp /tmp/crt.XXXXXXXXXX)
	trap "rm -Rf $$tempfile" 0 2 3 15
	key=ca.crt
	file=gitlab.$${KIND_CLUSTER_NAME}.lan.crt
	kubectl get secrets/gitlab-tls-certificate --context $${KUBE_CONTEXT} --namespace=$${HELM_NAMESPACE} -o jsonpath="{.data.$${key//./\\.}}" | base64 -d > $$tempfile
	nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); until [[ $$nb -eq 0 ]]; do sleep 1; certutil -d sql:$$HOME/.pki/nssdb -D -n "$${file}" && nb=$$(certutil -d sql:$$HOME/.pki/nssdb -L | sed -rn "/^$${file}\s+/p" | wc -l); done
	certutil -d sql:$$HOME/.pki/nssdb -A -t "CT,c,c" -n "$${file}" -i $$tempfile
	certutil -d sql:$$HOME/.pki/nssdb -L
	sudo cp $$tempfile /usr/local/share/ca-certificates/$${file}
	sudo update-ca-certificates
#################################################################################################################################
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

	app=minio
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app $$app --arg url "http://$${url}" '{"app": $$app, "url": $$url}' | yq e -P

	app=registry
	url=$$(kubectl get ingresses.networking.k8s.io $${HELM_RELEASE}-$$app --context $${KUBE_CONTEXT} -n $${HELM_NAMESPACE} -ojsonpath='{.spec.rules[0].host}')
	echo ---
	jq --null-input --arg app $$app --arg url "http://$${url}" '{"app": $$app, "url": $$url}' | yq e -P
###################################################################################################################################################################################
###################################################################################################################################################################################
BIN_DIR := ~/bin

install: ## install
install: install-docker install-kubectl prepare-env install-packages install-kind install-helm install-yq install-lens install-kubectx install-kubens

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
	packages="openssl kubectl jq jo dnsutils iputils-ping netcat procps curl mariadb-client libnss3-tools"; \
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

prepare-etc-hosts.d: ## prepare-etc-hosts.d
prepare-etc-hosts.d:
	if ! [[ -d /etc/hosts.d ]]; then \
		sudo mkdir -p /etc/hosts.d; \
	fi

	if ! [[ -f /etc/hosts.d/hosts ]]; then \
		sudo cp -a /etc/hosts /etc/hosts.d/hosts; \
	fi

	sudo chown -R root:root /etc/hosts.d
	sudo chmod 755 /etc/hosts.d
	sudo chmod 644 /etc/hosts.d/*

config-etc-hosts: ## config-etc-hosts
config-etc-hosts:
	set -e
	cd $(ROOT_DIR)
	if ! [[ -d /etc/hosts.d ]]; then \
		$(MAKE) prepare-etc-hosts.d; \
	fi
	for f in hosts*.conf; do \
		echo "file: $$f"; \
		file=$$(basename $$f)
		if ! [[ -f /etc/hosts.d/$$file ]]; then \
			echo "file need to be created: /etc/hosts.d/$$file"; \
			sudo cp $$f /etc/hosts.d/$$file; \
			sudo chmod 644 /etc/hosts.d/*; \
		else \
			echo "file already exists: /etc/hosts.d/$$file"; \
			sumf=$$(cat $$f | sha256sum | cut -d" " -f1)
			sumfile=$$(cat /etc/hosts.d/$$file | sha256sum | cut -d" " -f1)
			echo "checksum $$f: $$sumf"
			echo "checksum /etc/hosts.d/$$file: $$sumfile"
			if [[ "$$sumf" != "$$sumfile" ]]; then \
				echo "checksums are different"; \
				sudo cp $$f /etc/hosts.d/$$file; \
				sudo chmod 644 /etc/hosts.d/*; \
			else \
				echo "checksums are the same"; \
			fi
		fi
	done

	sumold=$$(cat /etc/hosts | sha256sum | cut -d" " -f1)
	sumnew=$$(cat /etc/hosts.d/* | sha256sum | cut -d" " -f1 )
	echo "checksum /etc/hosts: $$sumold"
	echo "checksum /etc/hosts.d/*: $$sumnew"
	if [[ "$$sumold" != "$$sumnew" ]]; then \
		echo "checksums are different"; \
		sudo bash -c "cat /etc/hosts.d/* > /etc/hosts"
	else \
		echo "checksums are the same"; \
	fi

remove-dnsmasq-and-restore-resolved: ## remove-dnsmasq-and-restore-resolved
remove-dnsmasq-and-restore-resolved:
	dnsmasq_svc_enabled=$$(systemctl list-unit-files|sed -rn "/^dnsmasq\.service\s+enabled/p"); \
	if [[ -n "$$dnsmasq_svc_enabled" ]]; then \
		sudo systemctl disable --now dnsmasq.service; \
		sudo systemctl stop dnsmasq.service; \
		test -f /etc/resolv.conf && sudo chattr -i /etc/resolv.conf && sudo rm /etc/resolv.conf; \
		sudo systemctl enable systemd-resolved; \
		sudo systemctl restart systemd-resolved; \
		sudo systemctl restart network-manager.service; \
	fi

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

	sudo cp dnsmasq*.conf /etc/dnsmasq.d &> /dev/null

	sudo systemctl disable --now systemd-resolved
	sudo systemctl enable dnsmasq
	sudo systemctl restart network-manager.service
	sudo systemctl restart dnsmasq

###################################################################################################################################################################################
###################################################################################################################################################################################

help:
	@grep -E '(^(\w+-?)+:.*?##.*$$)' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

