#!/bin/bash
#
# This script creates a Debian based LXC containier using the
# /usr/share/lxc/templates/lxc-debian template
#
# Configure the Debian sources and mirrors to use for the new container in the
# debSources.conf file.
# Define any extra packages to install using the extraPackages.conf file.

MYNAME=$(basename $0)
MYDIR=$(dirname $0)

### Set the Debian package sources and config from the debSources.conf
DEBMIRRORS=""
OTHERREPOS=""
PKGS=""
if [ -f "${MYDIR}/debSources.conf" ]; then
    source ${MYDIR}/debSources.conf || exit 1
    # Set the mirror option if we have MIRROR available
    [ -n "$MIRROR" ] && DEBMIRRORS="--mirror=\"$MIRROR\""
    # Set the security mirror option if we have SECURITY_MIRROR available
    [ -n "$SECURITY_MIRROR" ] && \
        DEBMIRRORS="$DEBMIRRORS --security-mirror=\"$SECURITY_MIRROR\""
    # The list of packages makes it easy for humans, now make it a proper
    # comma separated list for the command line option.
    PKGS=$(echo $PKGS | sed -r -e 's/[ ,]+/,/g' -e 's/,$//')
fi

# Source the list of extra packages to install
PKGS=""
if [ -f "${MYDIR}/extraPackages.conf" ]; then
    source ${MYDIR}/extraPackages.conf || exit 1
    # The list of packages makes it easy for humans, now make it a proper
    # comma separated list for the command line option.
    # First reomove all coments and empty lines
    PKGS=$(echo "$PKGS" | sed -r -e 's/(\s+)?#.*//' -e 's/\s+//' | grep -v "^$")
    # Now replace newlines with commas and remove any trailing commas
    PKGS=$(echo "$PKGS" | tr '\n' ',' | sed 's/,$//')
fi

# Default empty release name
REL=''
# Default empty container name
CNAME=''
# Default empty first user for container
USER1=''

##
# Show help
##
function usage() {
    sed 's/^    //' << __END__

    Usage: $MYNAME -n name [-r release] [-u username] [-h]

    Options:
      -n  the name for the new container
      -r  Debian release name (jessie, stretch, etc.) defaults to current stable.
      -u  name for the first user to create in the container. Does not create a
          user by default. Initial password will be the username - forced to
          change on first login.
      -k  Path to an ssh public key to add to the user's authorized_keys if a new
          user is created. Optional.
      -L  Use lvm as backingstore instead of directory. See -N, -V and -S options. 
      -N  The optional logical volume name use if the -L (lvm) option is on. The 
          default lv name is the same as that of the container.
      -V  The optional volume group to use for the logical volume if the -L (lvm)
          option is active. Default is to use the 'lxc' volume group.
      -S  The optional size for the logical volume when the -L (lvm) option is
          active. Specify the value as for the '--size' option to 'lvcreate'.
          The default is to create a 1GB volume.
      -h  show this help
    
__END__
}

##
# Parse options
##
function parseOpts() {
    OPTS='hr:n:u:k:LN:V:S:'
    # Note that we use "$@" to let each command-line parameter expand to a
    # separate word. The quotes around "$@" are essential!
    # We need TEMP as the 'eval set --' would nuke the return value of getopt.
    TEMP=$(getopt -o "$OPTS" -n "$MYNAME" -- "$@")

    # Note the quotes around "$TEMP": they are essential!
    eval set -- "$TEMP"
    unset TEMP

    while true; do
        case "$1" in
            '-h')
                usage
                exit 1
            ;;
            '-r')
                REL="$2"
                shift 2
                continue
            ;;
            '-n')
                CNAME="$2"
                shift 2
                continue
            ;;
            '-u')
                USER1="$2"
                shift 2
                continue
            ;;
            '-k')
                USER1KEY="$2"
                shift 2
                continue
            ;;
            '-L')
                LVM="on"
                shift 1
                continue
            ;;
            '-N')
                LVNAME="$2"
                shift 2
                continue
            ;;
            '-V')
                VGNAME="$2"
                shift 2
                continue
            ;;
            '-S')
                LVSIZE="$2"
                shift 2
                continue
            ;;
            '--')
                shift
                break
            ;;
            *)
                echo 'Internal error!' >&2
                exit 1
            ;;
        esac
    done

    # A key file is only allowed when a user is also created
    [ -n "$USER1KEY" -a -z "$USER1" ] && \
        echo "Can not add a public SSH key without a user." && exit 1
    # If a key file is given it should exist and be a valid public key
    if [ -n "$USER1KEY" ] ; then
        [ ! -r "$USER1KEY" ] && \
            echo "SSH pub key '$USER1KEY' does not exists, or is not readable." && \
            exit 1
        # Use file to try catch non public key
        (file "$USER1KEY" | grep -qiv public) && \
            echo "Does not seem to be a public SSH key: $USER1KEY" && exit 1
    fi
    # If any of the lvm options are given, the -L option is required
    if [ -n "$LVNAME" -o -n "$VGNAME" -o -n "$LVSIZE" ]; then
        [ -z "$LVM" ] && echo "When using any lvm options, -L is required." && \
            exit 1
    fi
}

##
# Creates the container using global variables
function createContainer() {
    # We need a name
    [ -z "$CNAME" ] && echo "Need a container name. Try -h option." && exit 2

    # Create the release arg and name if supplied
    REL=${REL:+"-r $REL"}
    # Create the backingstore args if lvm is needed
    BS=${LVM:+-B lvm${LVNAME:+ --lvname $LVNAME}${VGNAME:+ --vgname $VGNAME}${LVSIZE:+ --fssize $LVSIZE}}
    sudo lxc-create -n "$CNAME" -t debian $BS -- \
        $REL --mirror="$MIRROR" --security-mirror="$SECURITY_MIRROR" $OTHERREPOS \
        --packages="$PKGS"
}

##
# Checks that you are NOT root, but have sudo powers
##
function checkRoot() {
    [ "$(id -u)" = "0" ] && echo "You should not run this script as root, but you need sudo powers." && exit 3
    ! sudo /bin/true && echo "You do not seem to have sudo powers :-( " && exit 4
}



##
# Post install setup function
##
function postCreate() {
    # Commands to run in the new container to create the first user if needed.
    # These will be run as root in the container.
    CMD_USERCREATE="
    adduser --disabled-password --gecos='$USER1' $USER1 || exit 1
    echo '$USER1:$USER1' | chpasswd  # Set initial password
    chage -d 0 $USER1                # Force passw change on 1st login
    echo '$USER1  ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER1   # Allow sudo
    "
    # Commands to run in the new container to set up the new user after it has
    # been created. These will be run as the new user in the container.
    CMD_SETUPUSER="
    git clone https://github.com/fitzterra/easyEnv.git || exit
    cd easyEnv
    cp host_prompt_colors.dist host_prompt_colors
    sudo ./setupHost.sh
    ssh-keygen -t rsa -f /home/${USER1}/.ssh/id_rsa -N ''
    "
    # Command to copy the public key to the new user
    if [ -n "$USER1KEY" ]; then
        KEY="$(cat ${USER1KEY})"
        CMD_SETUP_AUTHKEY="
        echo '$KEY' >> ~/.ssh/authorized_keys
        chmod 700 ~/.ssh/authorized_keys
        "
    else
        CMD_SETUP_AUTHKEY=""
    fi

    # Start the container 
    sudo lxc-start -n $CNAME
    # It seems we need to wait for networking to come up properly before we can
    # continue
    sleep 5
    # Create the first user if needed
    if [ -n "$USER1" ]; then
        # First execute the commands to create the user via a bash shell that
        # will read commands from stdin.
        echo -e "$CMD_USERCREATE" | sudo lxc-attach -n $CNAME -- bash -s
        # Now execute the commands to set up the user
        echo -e "$CMD_SETUPUSER" | sudo lxc-attach -n $CNAME -- sudo -i -u $USER1 bash -s
        # Create autorized_keys if we have a pub key
        if [ -n "$CMD_SETUP_AUTHKEY" ]; then
            echo -e "$CMD_SETUP_AUTHKEY" | sudo lxc-attach -n $CNAME -- sudo -i -u $USER1 bash -s
        fi
    fi
}

# Check for root
##checkRoot
# Parse command line options
parseOpts $@
# Create the container
createContainer
# Set the container up
postCreate
