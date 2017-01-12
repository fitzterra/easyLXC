#!/bin/bash
#
# This script creates a Debian based LXC containier using the
# /usr/share/lxc/templates/lxc-debian template

MYNAME=$(basename $0)
# Set the package mirror env var
MIRROR=http://approx.gaul.za:9999/debian
SECURITY_MIRROR=http://approx.gaul.za:9999/security
# This option will enable the debian contrib and non-free repos in the container.
# Set it to the empty string to disbale this behaviour
OTHERREPOS='--enable-non-free'
# List of additional packages to install, one per line, all lines wrapped in
# one set of quotes.
PKGS="
aptitude
mc
git
vim-gtk
iputils-ping
sudo
less
bash-completion
ca-certificates
psmisc
"

# The list of packages above makes it easy for humans, no make it a proper
# comma separated list for the command line option.
PKGS=$(echo $PKGS | sed -r -e 's/[ ,]+/,/g' -e 's/,$//')

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
          user by default.
      -h  show this help
    
__END__
}

##
# Parse options
##
function parseOpts() {
    OPTS='hr:n:u:'
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
}

##
# Creates the container using global variables
function createContainer() {
    # We need a name
    [ -z "$CNAME" ] && echo "Need a container name. Try -h option." && exit 2

    # Create the release arg and name if supplied
    REL=${REL:+"-r $REL"}
    sudo lxc-create -n "$CNAME" -t debian -- \
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
    echo '$USER1:$USER1' | chpasswd
    echo '$USER1  ALL = NOPASSWD: ALL' > /etc/sudoers.d/$USER1
    "
    # Commands to run in the new container to set up the new user after it has
    # been created. These will be run as the new user in the container.
    CMD_SETUPUSER="
    git clone https://github.com/fitzterra/easyEnv.git || exit
    cd easyEnv
    cp host_prompt_colors.dist host_prompt_colors
    sudo ./setupHost.sh
    "

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
        # Now execute the 
        echo -e "$CMD_SETUPUSER" | sudo lxc-attach -n $CNAME -- sudo -i -u $USER1 bash -s
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
