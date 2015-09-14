#!/usr/bin/env bash
#
# Bootstrap script to configure all nodes.
#

export http_proxy=
export https_proxy=

if [ $2 = 'aio' ]; then
    # Run registry on port 4000 since it may collide with keystone when doing AIO
    REGISTRY_PORT=4000
    SUPPORT_NODE=operator
else
    REGISTRY_PORT=5000
    SUPPORT_NODE=support01
fi
REGISTRY=operator.local:${REGISTRY_PORT}

# Install common packages and do some prepwork.
function prep_work {
    systemctl stop firewalld
    systemctl disable firewalld

    # This removes the fqdn from /etc/hosts's 127.0.0.1. This name.local will
    # resolve to the public IP instead of localhost.
    sed -i -r "s/^(127\.0\.0\.1\s+)(.*) `hostname` (.+)/\1 \3/" /etc/hosts

    yum install -y http://mirror.nl.leaseweb.net/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
    yum install -y MySQL-python vim-enhanced python-pip python-devel gcc openssl-devel libffi-devel libxml2-devel libxslt-devel && yum clean all
    pip install --upgrade docker-py
}

# Install and configure a quick&dirty docker daemon.
function install_docker {
    # Allow for an externally supplied docker binary.
    if [ -f "/data/docker" ]; then
        cp /vagrant/docker /usr/bin/docker
        chmod +x /usr/bin/docker
    else
        cat >/etc/yum.repos.d/docker.repo <<-EOF
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
        # Also upgrade device-mapper here because of:
        # https://github.com/docker/docker/issues/12108
        yum install -y docker-engine device-mapper

        # Despite it shipping with /etc/sysconfig/docker, Docker is not configured to
        # load it from it's service file.
        sed -i -r "s,(ExecStart)=(.+),\1=/usr/bin/docker -d --insecure-registry ${REGISTRY} --registry-mirror=http://${REGISTRY}," /usr/lib/systemd/system/docker.service

        systemctl daemon-reload
        systemctl enable docker
        systemctl start docker
    fi

    usermod -aG docker vagrant
}

# Configure the operator node and install some additional packages.
function configure_operator {
    yum install -y git mariadb && yum clean all
    pip install --upgrade ansible python-openstackclient

    pip install ~vagrant/kolla

    # Note: this trickery requires a patched docker binary.
    if [ "$http_proxy" = "" ]; then
        su - vagrant sh -c "echo BUILDFLAGS=\\\"--build-env=http_proxy=$http_proxy --build-env=https_proxy=$https_proxy\\\" > ~/kolla/.buildconf"
    fi

    cp -r ~vagrant/kolla/etc/kolla/ /etc/kolla
    chown -R vagrant: /etc/kolla

    # Make sure Ansible uses scp.
    cat > ~vagrant/.ansible.cfg <<EOF
[defaults]
forks=100

[ssh_connection]
scp_if_ssh=True
EOF
    chown vagrant: ~vagrant/.ansible.cfg

    # The openrc file.
    cat > ~vagrant/openrc <<EOF
export OS_AUTH_URL="http://${SUPPORT_NODE}:35357/v2.0"
export OS_USERNAME=admin
export OS_PASSWORD=password
export OS_TENANT_NAME=admin
export OS_VOLUME_API_VERSION=2
EOF

    # Quick&dirty helper script to push images to the local registry's lokolla
    # namespace.
    cat > ~vagrant/tag-and-push.sh <<EOF
for image in \$(docker images|awk '/^kollaglue/ {print \$1}'); do
    docker tag \$image ${REGISTRY}/lokolla/\${image#kollaglue/}:latest
    docker push ${REGISTRY}/lokolla/\${image#kollaglue/}:latest
done
EOF
    chmod +x ~vagrant/tag-and-push.sh

    chown vagrant: ~vagrant/openrc ~vagrant/tag-and-push.sh

    # Launch a local registry (and mirror) to speed up pulling images.
    # 0.9.1 is actually the _latest_ tag.
    if [[ ! $(docker ps -a -q -f name=registry) ]]; then
        docker run -d \
            --name registry \
            --restart=always \
            -p $REGISTRY_PORT:5000 \
            -e STANDALONE=True \
            -e MIRROR_SOURCE=https://registry-1.docker.io \
            -e MIRROR_SOURCE_INDEX=https://index.docker.io \
            -e STORAGE_PATH=/var/lib/registry \
            -v /data/host/registry-storage:/var/lib/registry \
            registry:0.9.1
    fi
}

prep_work
install_docker

if [ "$1" = "operator" ]; then
    configure_operator
fi
