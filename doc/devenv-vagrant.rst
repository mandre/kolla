Vagrant up!
===========

This guide describes how to use `Vagrant <http://vagrantup.com>`__ to
assist in developing for Kolla.

Vagrant is a tool to assist in scripted creation of virtual machines, it will
take care of setting up CentOS-based VMs for Kolla development, each with
proper hardware like memory amount and number of network interfaces.

Getting Started
---------------

The Vagrant script proposes All-in-One or multi-node deployments, AIO being the
default.

In the case of multi-node deployment, the vagrant setup will build a cluster
with the following nodes by default:

-  3 control nodes
-  1 compute node
-  1 storage node
-  1 network node
-  1 operator node

These settings can be changed by editing the Vagrantfile.

Kolla runs from the operator node to deploy OpenStack.

All nodes are connected with each other on the secondary nic, the
primary nic is behind a NAT interface for connecting with the internet.
A third nic is connected without IP configuration to a public bridge
interface. This may be used for Neutron/Nova to connect to instances.

Start with downloading and installing the Vagrant package for your
distro of choice. Various downloads can be found
at the `Vagrant downloads <https://www.vagrantup.com/downloads.html>`__.

On Fedora 22 it is as easy as::

    sudo dnf install vagrant ruby-devel libvirt-devel

After we will install the hostmanager plugin so all hosts are recorded in
/etc/hosts (inside each vm)::

    vagrant plugin install vagrant-hostmanager

Vagrant supports a wide range of virtualization technologies, of which
we will use libvirt for now::

    vagrant plugin install vagrant-libvirt

We use NFS to share file between host and VMs::

    sudo systemctl start nfs-server
    firewall-cmd --permanent --add-port=2049/udp
    firewall-cmd --permanent --add-port=2049/tcp
    firewall-cmd --permanent --add-port=111/udp
    firewall-cmd --permanent --add-port=111/tcp

Find some place in your homedir and checkout the Kolla repo::

    git clone https://github.com/openstack/kolla.git ~/dev/kolla

You can now tweak the Vagrantfile or start a CentOS7-based environment right
away::

    cd ~/dev/kolla/vagrant && vagrant up

The command ``vagrant up`` will build your VMs , ``vagrant status`` will give
you a quick overview once done.

Vagrant Up
----------

Once vagrant has completed deploying all nodes, we can focus on
launching Kolla. First, connect with the *operator* node::

    vagrant ssh operator

To speed things up, there is a local registry running on the operator.
All nodes are configured so they can use this insecure repo to pull
from, and they will use it as mirror. Ansible may use this registry to
pull images from.

All nodes have a local folder shared between the group and the
hypervisor, and a folder shared between *all* nodes and the hypervisor.
This mapping is lost after reboots, so make sure you use the command
``vagrant reload <node>`` when reboots are required. Having this shared
folder you have a method to supply a different docker binary to the
cluster. The shared folder is also used to store the docker-registry
files, so they are save from destructive operations like
``vagrant destroy``.


Building images
^^^^^^^^^^^^^^^

All you need to do once logged on the *operator* VM is calling the
``kolla-build`` utility::

    kolla-build

``kolla-build`` accept arguments as documented in :doc:`image-building`.


Deploying OpenStack with Kolla
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Deploy AIO with::

    sudo kolla-ansible deploy

Deploy multinode with::

    sudo kolla-ansible deploy -i /usr/share/kolla/ansible/inventory/multinode

You can then check that your OpenStack is alive::

    source ~/openrc
    openstack user-list

Or navigate to http://10.10.10.254/.


Further Reading
---------------

All Vagrant documentation can be found at
`docs.vagrantup.com <http://docs.vagrantup.com>`__.
