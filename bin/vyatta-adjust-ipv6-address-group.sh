#!/bin/bash
# updates an ipv6-address-group, typically used in firewall rules to allow
# access to a local server from the web

# remembers the old address that was set in a tmpdir. Changes will only be made
# if the address changes.
EXIT_OK=0
EXIT_GENERAL_ERROR=1
EXIT_COMMAND_USAGE_ERROR=64
# store determined addresses here; creates one tmpfile for each configuration
tmpdir="/tmp/vyatta-ipv6-address-group-update"

CMD_WRAPPER="/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper"

# expect the first argument to this script point to a configuration file
# that provides necessary parameters
if [[ -z "$1" ]]; then
    echo "first argument must point to configuration file to load"
    exit $EXIT_COMMAND_USAGE_ERROR
fi
config="$1"

mkdir -vp "$tmpdir"

# use the configurations name within the tmpfile.
# If anyone would like to call this script with different configurations
# we must differentiate between them.
tmpfile="$tmpdir/$(basename "$config").txt"

check_prerequesites() {
    # check if the required configuration file is present and the variables
    # are set.
    if [[ -f "$config" ]]; then
        # shellcheck disable=SC1090
        source "$config"
    else
        echo "config file missing or not a file: $config"
        exit $EXIT_GENERAL_ERROR
    fi

    if [[ -z $INTERFACE ]]; then echo "INTERFACE not set, missing in config?"; exit 1; fi
    if [[ -z $INTERFACE_IDENTIFIER_HOST ]]; then echo "INTERFACE_IDENTIFIER_HOST not set, missing in config?"; exit 1; fi
    if [[ -z $IPV6_ADDRESS_GROUP_NAME ]]; then echo "IPV6_ADDRESS_GROUP_NAME not set, missing in config?"; exit 1; fi
}

determine_ip() {
    # determine the IP of the host by
    # - pulling the prefix from the corresponding network interface
    # - appending the interface identifier
    interface="$1"
    interface_identifier="$2"

    # scraping is always messy, but it is safe to assume that the prefix is at at least 6 characters long
    # and the routing rule in question is the first one listed
    prefix="$(ip -6 route show dev "$interface" | head -n 1 | grep -o -E "[0-9a-f:]{6,}")"

    # strip the extra colon from the end
    prefix="${prefix%:}"

    echo "${prefix}${interface_identifier}"
}

# taken from
# https://github.com/cennis91/edgeos-scripts/blob/ddc65d5abc6569c81dd7d2f5c9d5dc7791616bb4/lib/vyatta.sh#L37
# allows running a multiline configuration script
exec_vyatta_config() {
    # shellcheck disable=SC2155
    local commands="$*"

    "$CMD_WRAPPER" begin
    while read -r command; do
        if [[ -n "$command" && ! $command =~ ^[\ \t]*#.*$ ]]; then
            # shellcheck disable=SC2086
            eval "$CMD_WRAPPER" $command
        fi
    done < <(echo "$commands")
    "$CMD_WRAPPER" end
}


check_prerequesites
# shellcheck disable=SC1090
source "$config"

address_old="$(<"$tmpfile")"
address_new="$(determine_ip "$INTERFACE" "$INTERFACE_IDENTIFIER_HOST")"

# don't do anything if determining the new address failed
if [[ -z "$address_new" ]]; then
    echo "failed to determine IP, exiting."
    exit $EXIT_GENERAL_ERROR
fi

# vyatta config script definition; removes old entries from the address group, inserts
# new address
SCRIPT=$(cat <<EOF
    delete firewall group ipv6-address-group $IPV6_ADDRESS_GROUP_NAME ipv6-address
    set firewall group ipv6-address-group $IPV6_ADDRESS_GROUP_NAME ipv6-address $address_new
    commit
EOF
)

# update the address group if the address changed
if [[ "$address_old" != "$address_new" ]]; then
    echo "updating address from $address_old to $address_new"
    echo "$address_new" > "$tmpfile"

    exec_vyatta_config "$SCRIPT"
else
    echo "address still at $address_old, doing nothing"
fi

exit $EXIT_OK
