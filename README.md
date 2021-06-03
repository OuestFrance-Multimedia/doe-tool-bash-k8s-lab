# doe-scaffold-infrastructure-kind

Run a Kubernetes environment on your machine. Develop Helm Charts and deploy your App.

This allows in particular to :
- develop quickly Kubernetes infrasctructure
- develop without depending on external resources
- develop as close as possible to the final execution platform
- easily reproduce contexts
- implement & test scaling
- implement & test high availability
- realize chaos engineering

`You Build It, You Run It`

---

## [kind](https://kind.sigs.k8s.io/)
<p align="center"><img alt="kind" src="https://raw.githubusercontent.com/kubernetes-sigs/kind/main/logo/logo.png" width="300px" /></p>


[Kubernetes IN Docker](https://kind.sigs.k8s.io/) is a tool for running local Kubernetes clusters using Docker container “nodes”.
kind was primarily designed for testing Kubernetes itself, but may be used for local development or CI.

![](https://raw.githubusercontent.com/kubernetes-sigs/kind/main/site/static/images/kind-create-cluster.png)

### kubernetes version

You can choose your kubernetes version here: [https://hub.docker.com/r/kindest/node/tags](https://hub.docker.com/r/kindest/node/tags)

### configuration

You can customize kind cluster with an YAML file, folling example will create 1 control-plane and 1 worker. We affect a label to this worker.

```yaml
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
EOF
```

### volumes

You can share a local volume with kind cluster and mount it into your POD thanks [PV and PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

link: [https://stackoverflow.com/questions/62694361/how-to-reference-a-local-volume-in-kind-kubernetes-in-docker](https://stackoverflow.com/questions/62694361/how-to-reference-a-local-volume-in-kind-kubernetes-in-docker)

---

### [Helm - The package manager for Kubernetes](https://helm.sh/)

Helm is a tool for managing Charts. Charts are packages of pre-configured Kubernetes resources.

Use Helm to:
- Find and use popular software packaged as Helm Charts to run in Kubernetes
- Share your own applications as Helm Charts
- Create reproducible builds of your Kubernetes applications
- Intelligently manage your Kubernetes manifest files
- Manage releases of Helm packages

---

### [MetalLB](https://metallb.universe.tf/)

MetalLB is a load-balancer implementation for bare metal Kubernetes clusters, using standard routing protocols.
It handles the ServiceType: Loadbalancer.

We can use MetalLB in order to reserve an IP Address in docker network and expose our kubernetes services.

MetalLB is deploy with Helm Chart: https://hub.kubeapps.com/charts/bitnami/metallb/2.3.7

Example of an YAML config file:
```yaml
---
configInline:
  # The address-pools section lists the IP addresses that MetalLB is
  # allowed to allocate, along with settings for how to advertise
  # those addresses over BGP once assigned. You can have as many
  # address pools as you want.
  address-pools:
  - # A name for the address pool. Services can request allocation
    # from a specific address pool using this name, by listing this
    # name under the 'metallb.universe.tf/address-pool' annotation.
    name: generic-cluster-pool
    # Protocol can be used to select how the announcement is done.
    # Supported values are bgp and layer2.
    protocol: layer2
    # A list of IP address ranges over which MetalLB has
    # authority. You can list multiple ranges in a single pool, they
    # will all share the same settings. Each range can be either a
    # CIDR prefix, or an explicit start-end range of IPs.
    addresses:
    - 10.27.50.30-10.27.50.35
speaker:
  ## random 256 character alphanumeric string
  ## openssl rand -base64 256
  secretValue: |
    wruDKc9D8TDiopJ8HlYph2/JTMeBTsJV80p5N5uD1QJSEHH7gagm6K/OtEZuvmll
    9ggkaZp/55CF/rvxVGhoqH1lVASv28zBGx4OskWN7wMqOPdEed48RFLi41+3N2RA
    WBoc4prQV8LWLLq8+xWC7Mh2iDzlXFhDTjVMAqtEAFVX7uZ+1MbPMkBm2Qt/QJSl
    rzZjVQ1KBc3Vxc6STCp6iQjVrrm2dBz8/FrrziEfLRmF8JzQHethE2c8Wn/1JNvj
    Ma1g8Bj1nCH8nGddOAlQ8lu7yLpuVMYXtDYWXzknRc4A7IAMcdREZL5FQMYpu19g
    1Xa2rGCUkJ/S2lVwc4EzaQ==
```

### [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)

Metrics Server is a scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling pipelines.

Metrics Server collects resource metrics from Kubelets and exposes them in Kubernetes apiserver through Metrics API for use by [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) and Vertical Pod Autoscaler. Metrics API can also be accessed by kubectl top, making it easier to debug autoscaling pipelines.

```bash
$ kubectl top pods --all-namespaces
NAMESPACE     NAME                                                              CPU(cores)   MEMORY(bytes)   
kube-system   alb-ingress-controller-aws-alb-ingress-controller-67d7cf85lwdg2   3m           10Mi            
kube-system   aws-node-9nmnw                                                    2m           20Mi            
kube-system   coredns-7bcbfc4774-q4pjj                                          2m           7Mi             
kube-system   coredns-7bcbfc4774-wwlcr                                          2m           7Mi             
kube-system   external-dns-54df666786-2ld9w                                     1m           12Mi            
kube-system   kube-proxy-ss87v                                                  2m           10Mi            
kube-system   kubernetes-dashboard-5478c45897-fcm48                             1m           12Mi            
kube-system   metrics-server-5f64dbfb9d-fnk5r                                   1m           12Mi            
kube-system   tiller-deploy-85744d9bfb-64pcr                                    1m           29Mi
```

Metrics Server is not meant for non-autoscaling purposes. For example, don't use it to forward metrics to monitoring solutions, or as a source of monitoring solution metrics.

Metrics Server offers:

- A single deployment that works on most clusters (see Requirements)
- Fast autoscaling, collecting metrics every 15 seconds.
- Resource efficiency, using 1 mili core of CPU and 2 MB of memory for each node in a cluster.
- Scalable support up to 5,000 node clusters.

MetalLB is deploy with Helm Chart: https://hub.kubeapps.com/charts/bitnami/metrics-server/5.8.9

Example of an YAML config file:
```yaml
---
apiService:
  create: true
extraArgs:
  kubelet-insecure-tls: true
  kubelet-preferred-address-types: InternalIP
```

# Tools

Packages / binaries:
- docker
- kind
- helm
- kubectl
- kubectx
- kubens
- jq
- yq
- lens
- dnsmasq

## [kubectl - The Kubernetes command-line tools](https://github.com/kubernetes/kubectl)

<p align="center"><img alt="kubectl" src="https://raw.githubusercontent.com/kubernetes/kubectl/master/images/kubectl-logo-medium.png" width="300px" /></p>


The Kubernetes command-line tool, kubectl, allows you to run commands against Kubernetes clusters. You can use kubectl to deploy applications, inspect and manage cluster resources, and view logs.


## [kubectx](https://github.com/ahmetb/kubectx)
kubectx is a utility to manage and switch between kubectl contexts.

![kubectx demo GIF](https://raw.githubusercontent.com/ahmetb/kubectx/master/img/kubectx-demo.gif)

## [kubens](https://github.com/ahmetb/kubectx)
kubens is a utility to switch between Kubernetes namespaces.

![kubens demo GIF](https://raw.githubusercontent.com/ahmetb/kubectx/master/img/kubens-demo.gif)

## [Lens - The Kubernetes IDE](https://github.com/lensapp/lens)

Lens IDE provides the full situational awareness for everything that runs in Kubernetes. It's lowering the barrier of entry for people just getting started and radically improving productivity for people with more experience.

[![Screenshot](https://raw.githubusercontent.com/lensapp/lens/master/.github/screenshot.png)](https://www.youtube.com/watch?v=eeDwdVXattc)

# Usage

## Install tools
Use the following command in order to install tools
```bash
make install
```

## Config file

Create .env file with following vars:
| var                          	| definition                               	| more                                       	| example                  	|
|------------------------------	|------------------------------------------	|--------------------------------------------	|--------------------------	|
| KIND_CLUSTER_NAME            	| cluster name                             	|                                            	| changeme                 	|
| KIND_CLUSTER_IMAGE           	| cluster image tag                        	| https://hub.docker.com/r/kindest/node/tags 	| kindest/node:v1.19.4     	|
| NETWORK_PREFIX               	| network prefix                           	| CIDR: 172.17.0.0/16                        	| 172.17                   	|
| METALLB_SPEAKER_SECRET_VALUE 	| random 256 character alphanumeric string 	| $(openssl rand -base64 256\|tr -d '\n')    	| bpP0AGV07oQt9jjNINJQFQ== 	|

Example:
```bash
cat << EOF > .env
KIND_CLUSTER_NAME=changeme
KIND_CLUSTER_IMAGE=kindest/node:v1.19.7
NETWORK_PREFIX=172.17
METALLB_SPEAKER_SECRET_VALUE=$(openssl rand -base64 256|tr -d '\n')
EOF
```

## Manage your cluster

### Create
```bash
make create
```

![kubens demo GIF](.github/create.gif)

### Destroy
```bash
make destroy
```

## DNS (Domain Name System)

### create your DNS config

By default, a explicit start-end range of IPs is reserved for MetalLB : `${NETWORK_PREFIX}.255.1-${NETWORK_PREFIX}.255.254`

`Choose an IP Address in MetalLB IP address ranges and affect it to a fqdn`

Example
```bash
cat << EOF > dnsmasq-example.conf
address=/server.domain.tld/172.17.255.1
EOF
```
`each file with following pattern: dnsmasq*.conf will be copied into dnsmasq config folder`

### apply DNS config

```bash
make config-dnsmasq
```

### What's happened ?

1. remove immutable attribute on /etc/resolv.conf
2. delete /etc/resolv.conf
3. add 127.0.0.1 into /etc/resolv.conf
4. add DNS server gived by DHCP server into /etc/resolv.conf
5. add 8.8.8.8 (google DNS server) into /etc/resolv.conf
6. add immutable attribute on /etc/resolv.conf
7. declare port 53 and host 127.0.0.1 in dnsmasq config file
8. copy dnsmasq*.conf files into dnsmasq config folder
9. disable service systemd-resolved
10. restart service dnsmasq

`YOU NEED TO APPLY DNS CONFIG EACH TIME YOU CHANGE NETWORK CONTEXT, EXAMPLE: VPN CONNECTION ETC`

