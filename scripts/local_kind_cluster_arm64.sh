#!/usr/bin/env bash

# This script was tested on Ubuntu 20.04.5

apt -y update
apt -y upgrade
set -e

## configure your lacal setup
export MY_SSH_KEY=""
export MY_USERNAME=""
export MY_GITHUB_TOKEN=""
export MY_GITHUB_REPO=""
export MY_SNAP="remove"
## if you want too KEEP snap stuff
# export MY_SNAP="keep"

echo "Setup SSH configuration for root"
###
grep -qxF ${MY_SSH_KEY} /root/.ssh/authorized_keys || cat << EOF > /root/.ssh/authorized_keys
${MY_SSH_KEY}
EOF
if $(sed -i -e 's/#PubkeyAuthentication/PubkeyAuthentication/g' /etc/ssh/sshd_config); then systemctl restart sshd; fi

echo "Fix user ${MY_USERNAME} to allow all access via sudo"
###
grep -qxF "${MY_USERNAME} ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/90-cloud-init-users || echo "${MY_USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-cloud-init-users

echo "${MY_SNAP} all the snap stuff"
##
if [ ${MY_SNAP} == "remove" ]; then
  if snap; then snap remove amazon-ssm-agent; fi
  for app in $(find /snap/core18/ -regex '.*[0-9]'); do umount $app; done
  if snap; then snap remove lxd; fi
  for app in $(find /snap/core20/ -regex '.*[0-9]'); do umount $app; done
  if snap; then rm -rf ~/snap /snap /var/snap /var/lib/snapd; fi
  apt-get purge -y snapd
fi

echo "Install all files needed"
###
apt -y install net-tools ca-certificates curl gnupg lsb-release jq

echo "Setup ulimits"
###
grep -qF "fs.file-max = 65535" /etc/sysctl.conf || echo "fs.file-max = 65535" >> /etc/sysctl.conf
grep -qF "nproc" /etc/security/limits.conf | grep -qxF "65535" || cat << EOF >> /etc/security/limits.conf
* soft     nproc          65535
* hard     nproc          65535
* soft     nofile         65535
* hard     nofile         65535
root soft     nproc          65535
root hard     nproc          65535
root soft     nofile         65535
root hard     nofile         65535
EOF

grep -qF "session required pam_limits.so" /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session
grep -qF "session required pam_limits.so" /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive
sysctl -p

if test -f /etc/netplan/01-kind-local.yaml; then
  echo "already created all the yaml-stuff we need initially"
else
  cat << EOF > /etc/netplan/01-kind-local.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:
      dhcp4: true
      addresses:
        - 10.0.2.23/24
EOF
  netplan apply
  systemctl mask systemd-resolved
  rm -f /etc/resolv.conf
  ln -s /files/resolv.conf /etc/resolv.conf
fi

if test -d /etc/docker; then
  echo "already created docker setup files"
else
  mkdir /etc/docker
  cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100M"
  },
  "storage-driver": "overlay2"
}
EOF
fi

if test -d /files; then
  echo "already created /files and content"
else
  mkdir -p /files
  cat << EOF >/files/resolv.conf
nameserver 8.8.8.8
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
EOF
  cp /files/resolv.conf /etc/resolv.conf.k8s
fi

if test -f /root/kind-cluster.yaml; then
  echo "already created the kind-cluster setup files"
else
  cat << EOF >/root/kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: local
networking:
  ipFamily: "ipv4"
  disableDefaultCNI: true
  kubeProxyMode: "none"
  podSubnet: "172.20.0.0/16"
  serviceSubnet: "172.21.0.0/16"
  apiServerAddress: "10.0.2.23"
  apiServerPort: 6443
kubeadmConfigPatches:
  - |
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: ClusterConfiguration
    apiServer:
      timeoutForControlPlane: 10m
      extraArgs:
        allow-privileged: "true"
        audit-log-path: /audit/k8s-api-audit.log
        audit-log-maxage: "7"
        audit-log-maxbackup: "4"
        audit-log-maxsize: "100"
        # audit-policy-file: /audit/audit-policy.yaml
        authorization-mode: Node,RBAC
        # feature-gates: VolumeSnapshotDataSource=true
        oidc-issuer-url: https://accounts.google.com
        oidc-username-claim: email
        oidc-client-id: 94966426663-0d0gfifjf9bc6sbi2jq8uherghi1bh2c.apps.googleusercontent.com
      extraVolumes:
        - name: audit-kubernetes
          hostPath: /var/log/kubernetes
          mountPath: /audit
          readOnly: false
          pathType: DirectoryOrCreate
    controllerManager:
      extraArgs:
        allocate-node-cidrs: "true"
        cluster-cidr: 172.20.0.0/16
        # feature-gates: VolumeSnapshotDataSource=true
        node-cidr-mask-size: "24"
    controlPlaneEndpoint: 10.0.2.23:6443
  - |
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    cgroupDriver: systemd
    clusterDNS:
      - 172.21.0.10
    clusterDomain: cluster.local
    serializeImagePulls: false
    resolvConf: "/files/resolv.conf"

nodes:
  - role: control-plane
    extraMounts:
      - hostPath: /files
        containerPath: /files
        propagation: HostToContainer
    kubeadmConfigPatches:
      - |
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: InitConfiguration
        nodeRegistration:
          name: control-plane
          taints: []
  - role: worker
    extraMounts:
      - hostPath: /files
        containerPath: /files
        propagation: HostToContainer
    kubeadmConfigPatches:
      - |
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: JoinConfiguration
        nodeRegistration:
          name: worker-1
          taints: []
  - role: worker
    extraMounts:
      - hostPath: /files
        containerPath: /files
        propagation: HostToContainer
    kubeadmConfigPatches:
      - |
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: JoinConfiguration
        nodeRegistration:
          name: worker-2
          taints: []
  - role: worker
    extraMounts:
      - hostPath: /files
        containerPath: /files
        propagation: HostToContainer
    kubeadmConfigPatches:
      - |
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: JoinConfiguration
        nodeRegistration:
          name: worker-3
          taints: []
EOF
fi

if dpkg -l | grep -q frr; then
  echo "already installed and configured FRR for BGP routing"
else
  ## if you are on amd64
  #apt -y install frr

  ## if you are on arm64
  # add GPG key
  curl -s https://deb.frrouting.org/frr/keys.asc | sudo apt-key add -

  # possible values for FRRVER: frr-6 frr-7 frr-8 frr-stable
  # frr-stable will be the latest official stable release
  FRRVER="frr-stable"
  echo deb https://deb.frrouting.org/frr $(lsb_release -s -c) $FRRVER | sudo tee -a /etc/apt/sources.list.d/frr.list

  # update and install FRR
  apt-get update && apt-get install -y frr frr-pythontools

  cat << 'EOF' > /etc/frr/frr.conf
# default to using syslog. /etc/rsyslog.d/45-frr.conf places the log
# in /var/log/frr/frr.log
# log syslog informational
frr version 8.1.1
frr defaults traditional
hostname external-router
debug bgp updates
debug bgp keepalives
log syslog informational
log file /tmp/frr.log
log timestamp precision 3
no ipv6 forwarding
service integrated-vtysh-config
!
router bgp 65000
 bgp router-id 172.18.0.1
 no bgp ebgp-requires-policy
 no bgp default ipv4-unicast
 neighbor 172.18.0.2 remote-as 65100
 neighbor 172.18.0.3 remote-as 65100
 neighbor 172.18.0.4 remote-as 65100
 neighbor 172.18.0.5 remote-as 65100
!
address-family ipv4 unicast
 neighbor 172.18.0.2 activate
 neighbor 172.18.0.2 next-hop-self
 neighbor 172.18.0.3 activate
 neighbor 172.18.0.3 next-hop-self
 neighbor 172.18.0.4 activate
 neighbor 172.18.0.4 next-hop-self
 neighbor 172.18.0.5 activate
 neighbor 172.18.0.5 next-hop-self
 maximum-paths 32
exit-address-family
!
line vty
!
EOF

  cat << 'EOF' > /etc/frr/daemons
# This file tells the frr package which daemons to start.
#
# Sample configurations for these daemons can be found in
# /usr/share/doc/frr/examples/.
#
# ATTENTION:
#
# When activation a daemon at the first time, a config file, even if it is
# empty, has to be present *and* be owned by the user and group "frr", else
# the daemon will not be started by /etc/init.d/frr. The permissions should
# be u=rw,g=r,o=.
# When using "vtysh" such a config file is also needed. It should be owned by
# group "frrvty" and set to ug=rw,o= though. Check /etc/pam.d/frr, too.
#
# The watchfrr and zebra daemons are always started.
#
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
#bfdd=yes
bfdd=no

# If this option is set the /etc/init.d/frr script automatically loads
# the config via "vtysh -b" when the servers are started.
# Check /etc/pam.d/frr if you intend to use "vtysh"!
#
vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
bgpd_options="   -A 127.0.0.1"
ospfd_options="  -A 127.0.0.1"
ospf6d_options=" -A ::1"
ripd_options="   -A 127.0.0.1"
ripngd_options=" -A ::1"
isisd_options="  -A 127.0.0.1"
pimd_options="   -A 127.0.0.1"
ldpd_options="   -A 127.0.0.1"
nhrpd_options="  -A 127.0.0.1"
eigrpd_options=" -A 127.0.0.1"
babeld_options=" -A 127.0.0.1"
sharpd_options=" -A 127.0.0.1"
pbrd_options="   -A 127.0.0.1"
staticd_options="-A 127.0.0.1"
bfdd_options="   -A 127.0.0.1"

# The list of daemons to watch is automatically generated by the init script.
# watchfrr_options=""

# for debugging purposes, you can specify a "wrap" command to start instead
# of starting the daemon directly, e.g. to use valgrind on ospfd:
#   ospfd_wrap="/usr/bin/valgrind"
# or you can use "all_wrap" for all daemons, e.g. to use perf record:
#   all_wrap="/usr/bin/perf record --call-graph -"
# the normal daemon command is added to this at the end.
EOF
  systemctl restart frr
fi

if test -f /etc/apt/keyrings/docker.gpg; then
  echo "already installed docker"
else
  mkdir -p /etc/apt/keyrings
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  apt -y update
  apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
  apt -y clean
fi

if test -f /usr/bin/kubectl; then
  echo "already installed kubectl"
else
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
  chmod +x ./kubectl
  mv ./kubectl /usr/bin
fi

if test -f /usr/bin/k9s; then
  echo "already installed k9s for convinience"
else
  curl -LO https://github.com/derailed/k9s/releases/download/v0.26.5/k9s_Linux_arm64.tar.gz
  tar xvf k9s_Linux_arm64.tar.gz -C /usr/bin
fi

if test -f /usr/bin/helm; then
  echo "already installed helm for templating"
else
  curl -LO https://get.helm.sh/helm-v3.9.4-linux-arm64.tar.gz
  tar xvf helm-v3.9.4-linux-arm64.tar.gz
  mv /root/linux-arm64/helm /usr/bin/helm
  helm repo add aws-cloud-controller-manager https://kubernetes.github.io/cloud-provider-aws
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
  helm repo add minio https://operator.min.io/
  helm repo add hashicorp https://helm.releases.hashicorp.com
  helm repo add cilium https://helm.cilium.io/
  helm repo add enix https://charts.enix.io/
  helm repo update
fi

if test -f /root/cilium-1.12.9-direct-routing-local.yaml; then
  echo "already installed cilium-1.12.2-direct-routing-local"
else
  helm template cilium/cilium \
    --version 1.12.9 \
    --namespace=kube-system \
    --set kubeProxyReplacement="strict" \
    --set autoDirectNodeRoutes=true \
    --set cluster.name="local" \
    --set cluster.id=222 \
    --set bgp.enabled=true \
    --set bgp.announce.loadbalancerIP=true \
    --set bgp.announce.podCIDR=true \
    --set bgpControlPlane.enabled=true \
    --set healthPort=9877 \
    --set ingressController.enabled=true \
    --set ipam.mode=kubernetes \
    --set ipam.operator.clusterPoolIPv4PodCIDR="172.20.0.0/16" \
    --set ipam.operator.clusterPoolIPv4MaskSize=24 \
    --set kubeProxyReplacementHealthzBindAddr="0.0.0.0:10256" \
    --set enableIPv4Masquerade=true \
    --set k8s.requireIPv4PodCIDR=true \
    --set k8sServiceHost="10.0.2.23" \
    --set k8sServicePort="6443" \
    --set loadBalancer.mode=hybrid \
    --set tunnel="disabled" \
    --set operator.prometheus.enabled=true \
    --set ipv4NativeRoutingCIDR="172.16.0.0/12" \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    > /root/cilium-1.12.9-direct-routing-local.yaml
  cat << 'EOF' > /root/cilium.bgp-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: bgp-config
  namespace: kube-system
data:
  config.yaml: |
    peers:
      - peer-address: 172.18.0.1
        peer-asn: 65000
        my-asn: 65100
    address-pools:
      - name: default
        protocol: bgp
        addresses:
          - 172.18.0.100-172.18.0.200
EOF
fi

if test -f /root/cilium-1.12.9-direct-routing-ebpf.yaml; then
  echo "already installed cilium-1.12.9-direct-routing-ebpf"
else
  helm template cilium/cilium \
    --version "1.12.9" \
    --kube-version="1.25.0" \
    --namespace="kube-system" \
    --set cluster.id=222 \
    --set cluster.name="local" \
    --set k8sServiceHost="10.0.2.23" \
    --set k8sServicePort="6443" \
    --set kubeProxyReplacement="strict" \
    --set kubeProxyReplacementHealthzBindAddr="0.0.0.0:10256" \
    --set healthPort="9877" \
    --set tunnel="disabled" \
    --set autoDirectNodeRoutes="true" \
    --set k8s.requireIPv4PodCIDR="true" \
    --set ipv4NativeRoutingCIDR="172.20.0.0/16" \
    --set ipam.mode="kubernetes" \
    --set ipam.operator.clusterPoolIPv4PodCIDR="172.20.0.0/16" \
    --set ipam.operator.clusterPoolIPv4MaskSize="24" \
    --set bgpControlPlane.enabled="true" \
    --set bgp.enabled="true" \
    --set bgp.announce.loadbalancerIP="true" \
    --set bgp.announce.podCIDR="true" \
    --set installIptablesRules="true" \
    --set l7Proxy="true" \
    --set installNoConntrackIptablesRules="true" \
    --set bpf.masquerade="true" \
    --set bpf.hostLegacyRouting="false" \
    --set bpf.lbExternalClusterIP="true" \
    --set ipMasqAgent.enabled="true" \
    --set loadBalancer.mode="hybrid" \
    --set loadBalancer.acceleration="disabled" \
    --set socketLB.hostNamespaceOnly="true" \
    --set enableCiliumEndpointSlice="true" \
    --set bandwidthManager.enabled="true" \
    --set prometheus.enabled="true" \
    --set operator.prometheus.enabled="true" \
    --set hubble.enabled="true" \
    --set hubble.metrics.enabled='{dns,drop,tcp,flow,icmp,http}' \
  > /root/cilium-1.12.9-direct-routing-ebpf.yaml
    cat << 'EOF' > /root/ip-masq-agent.cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
      - 10.0.0.0/10
      - 10.64.0.0/13
      - 10.72.0.0/15
      - 10.74.0.0/16
      - 10.75.0.0/16
      - 10.76.0.0/14
      - 10.80.0.0/14
      - 10.84.0.0/16
      - 10.85.0.0/16
      - 10.86.0.0/15
      - 10.88.0.0/13
      - 10.96.0.0/11
      - 10.128.0.0/9
      - 172.16.0.0/12
      - 192.168.0.0/16
    masqLinkLocal: true
EOF
    cat << 'EOF' > /root/bgp-peering-policy-local.yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy-training
spec: # CiliumBGPPeeringPolicySpec
  nodeSelector:
    matchLabels:
      klessen.cloud/bgp: training
  virtualRouters: # []CiliumBGPVirtualRouter
    - localASN: 65100
      exportPodCIDR: true
      neighbors: # []CiliumBGPNeighbor
        - peerAddress: '172.18.0.2/32'
          peerASN: 65100
        - peerAddress: '172.18.0.3/32'
          peerASN: 65100
        - peerAddress: '172.18.0.4/32'
          peerASN: 65100
        - peerAddress: '172.18.0.5/32'
          peerASN: 65100
EOF
fi

if test -f /usr/bin/kind; then
  echo "already installed KIND v0.15.0"
else
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.15.0/kind-linux-arm64
  chmod +x ./kind
  mv ./kind /usr/bin
fi

## add while not failed loop
if [[ $(kind get clusters) == "local" ]]; then
  echo "already created KIND cluster local"
else
  kind create cluster --config /root/kind-cluster.yaml
  kubectl apply -f /root/cilium-1.12.9-direct-routing.yaml -f /root/cilium.bgp-config.yaml -f /root/bgp-peering-policy-local.yaml -f /root/ip-masq-agent.cm.yaml --server-side
  sleep 90
fi

if [[ $(kubectl krew) ]]; then
  echo "already installed kubectl krew plugin manager"
else
  OS="$(uname | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')"
  KREW="krew-${OS}_${ARCH}"
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
  tar zxvf "${KREW}.tar.gz"
  ./"${KREW}" install krew
  echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /root/.bashrc
fi

if [[ $(gh) ]]; then
  echo "already installed github CLI tool gh"
else
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt -y update
  apt -y install gh
  apt -y clean
fi

if [[ $(flux) ]]; then
  echo "already installed flux-v2 for the local cluster"
else
  export GITHUB_TOKEN=${MY_GITHUB_TOKEN}
  curl -s https://fluxcd.io/install.sh | bash
  . <(flux completion bash)
fi
