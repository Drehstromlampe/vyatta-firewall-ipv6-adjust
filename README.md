# Problem

When running a server behind a firewall that is accessible via IPv6, the routers firewall must accept incoming traffic from the web to a
specific server. A change of the IPv6-prefix will render the firewall configuration ineffective.

# Solution

The solution is to periodically query an interfaces IPv6-prefix. If it changes, the firewall configuration will be adjusted, just like
dyndns-clients do this for DNS-records.

The script was tested on an edgerouter 12p running EdgeOS v3.0.1

# Prerequesites

In order to get the script running, the following things must be available

- you can copy files to and from your router using [SCP](https://en.wikipedia.org/wiki/Secure_copy_protocol)
- naturally, you have [IPv6 set up](https://help.ui.com/hc/en-us/articles/36378535649687-Configuring-IPv6-in-UniFi), typically with
  [prefix delegation](https://daniel.washburn.at/howtos/edgeos-dhcpv6-pd) for the interface your server is connected to.
- you have set up the
  [zone-based firewall on the edgerouter](https://help.uisp.com/hc/en-us/articles/22591212263191-EdgeRouter-Zone-Based-Firewall) (may not
  strictly be necessary but it makes sense for dualstak networks)
- you have an `ipv6-address-group` defined which contains the public address of your server. This address group is referenced by whatever
  firewall rule accepts incoming traffic to your server

# Setup

The script is configurable via a sourcable configuration file. The configuration file tells the script

- which interface should be queried to determine the IPv6-prefix
- the host-part (IPv6 interface identifier) of the address of your server
- the name of the `ipv6-address-group` that must be updated.

## Create a configuration file

Example configuration:

```
INTERFACE=switch0.11
INTERFACE_IDENTIFIER_HOST=5054:ff:fe55:5555
IPV6_ADDRESS_GROUP_NAME=gitlab-pub
```

## Copy over the script

Copy the script to your router using scp, e.g. to `/opt/vyatta-firewall-ipv6-adjust`.

## Copy the configuration to the router

Create a directory on the target for storing the configuraiton, e.g. `/etc/vyatta-ipv6-address-group-adjust.d`

Copy your configuration file to this directory.

## setting up the timer

You do not need to define a cronjob by hand. The Edgerouter/vyatta allows you to define a job. As usually, this can be done using the Config
Tree or the command line.

```
set system task-scheduler task gitlab-ipv6-update executable arguments /etc/vyatta-ipv6-address-group-adjust.d/gitlab
set system task-scheduler task gitlab-ipv6-update executable path /opt/vyatta-firewall-ipv6-adjust/vyatta-adjust-ipv6-address-group.sh
set system task-scheduler task gitlab-ipv6-update interval 5m
```

# Verifying that it works

1. you should see a temporary directory that stores the full IPv6-address in `/tmp/vyatta-ipv6-address-group-update/`
2. remove the temporary file and drop the address from the `ipv6-address-group`, do not delete the address group itself. The address should
   be added automatically when the timer triggers again.
