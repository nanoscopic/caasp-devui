# caasp-devui
Developer UI for SUSE CaaSP 

This project is a simple Perl cgi script designed for displaying debugging information about a local kvm developer environment of SUSE CaaSP.

By developer environment of CaaSP, what is meant is a instance of CaaSP created by using the caasp-devenv script from https://github.com/kubic-project/automation

## Project Status
The devui should be viewed as an alpha project. It was hacked together quickly to help with general debugging and understanding of the internal setup of a CaaSP developer environment. It should not be considered production ready, nor relied on for any specific purpose at this time. It is subject to arbitrary change by the whim of myself, the current sole user and developer of this tool.

## Installation on SUSE Tumbleweed
* sudo zyppper in apache2 ( if it was not already installed )
* mkdir ~/github
* cd ~/github
* git clone git@github.com:nanoscopic/caasp-devui.git
* mkdir -p /srv/www/caasp-devui
* sudo ln -s /home/[username]/github/caasp-devui/caasp-devui.pl /srv/www/caasp-devui.pl
* sudo ln -s /home/[username]/github/caasp-devui/apache.conf /etc/apache2/conf.d/caasp-devui.conf
* Add apache2 user into appropriate groups to access qemu/virsh. WARNING: This makes it possible for any scripts running within Apache to access your virts. Depending on your setting this may not be acceptable from a security standpoint.
* Add a fake host entry to /etc/hosts to access caasp-devui through
* sudo systemctl restart apache2 ( or possible just start it )

## Use Cases
* View information about the docker pods / layers that the cluster is composed of
* View the cloud init config for the CaaSP cluster nodes ( admin, master, workers )
* Show information about the cluster nodes including their IP addresses

## Todo
* Add a spec file to build a rpm package for quickly deploying this without the install steps
* One spec file is created, add this project into build.opensuse.com so that it becomes available within Tumbleweed
* Add in Salt state debugging for the initial deployment of a CaaSP / kubic developer environment

## FAQ
* Q: How do I get a developer environment of CaaSP up and running as a non-employee of SUSE?
* * A: Right now the caasp-devenv script is not setup to do so. It currently depends on a SLE velum image only available internally. It should be possible to create a similar image based on Tumbleweed, but one is not currently being built and provided.
