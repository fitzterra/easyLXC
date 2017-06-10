Easy setup and configuration of LXC containers
==============================================

This is a system to easily:

* Create an LXC contianer
* Set up the first user in the container so the container is accessible via ssh
  for that user.

This is still a work in progress, and the initial requirements to be met:

* Only concerned to work on Debian systems at the moment, and specifically
  Jessie and Stretch
* Only concerned about creating __priviledged containers__ for now. My
  requirements for containers at the moment is splitting out into separate
  services and not so much about security.


Usage
-----

Use the `-h` command line option for for help.

The Debian Package Source mirrors for the container can be configured in the
`debSources.conf` file. This file also has options to enable the contrib and
non-free sources.

A list of additional packages to install in the new container can be supplied in
the `extraPackages.conf` file.

