#!/bin/sh
###############################################
#
# Nagios script to check network I/O status
#
# Copyright 2007, 2008 Ian Yates
#
# See usage for command line switches
#
# NOTE: Because of the method of gathering information, bytes/s values are calculated here, so no wanring/critical values can be set to trigger.
#       Consequently, this check plugin always returns OK.
#       This plugin is a means of returning stats to nagios for graphing (recommend DERIVE graph in RRD)
#
# Created: 2007-09-06 (i.yates@uea.ac.uk)
# Updated: 2007-09-06 (i.yates@uea.ac.uk)
# Updated: 2008-11-27 (i.yates@uea.ac.uk) - Added GPLv3 licence
# Updated: 2017-01-27 (www.claudiokuenzler.com) - Added validation checks and compatibility with CentOS/RHEL 7
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################

. /usr/lib/nagios/plugins/utils.sh


VERSION="1.1"

IFCONFIG=/sbin/ifconfig
GREP=/bin/grep
CUT=/usr/bin/cut

FLAG_VERBOSE=FALSE
INTERFACE=""
LEVEL_WARN="0"
LEVEL_CRIT="0"
RESULT=""
EXIT_STATUS=$STATE_OK



###############################################
#
## FUNCTIONS
#

## Print usage
usage() {
        echo " check_netio $VERSION - Nagios network I/O check script"
        echo ""
        echo " Usage: check_netio {-i} [ -v ] [ -h ]"
        echo ""
        echo "           -i  Interface to check (e.g. eth0)"
        echo "           -v  Verbose output (ignored for now)"
        echo "           -h  Show this page"
        echo ""
}

## Process command line options
doopts() {
        if ( `test 0 -lt $#` )
        then
                while getopts i:vh myarg "$@"
                do
                        case $myarg in
                                h|\?)
                                        usage
                                        exit;;
                                i)
                                        INTERFACE=$OPTARG;;
                                v)
                                        FLAG_VERBOSE=TRUE;;
                                *)      # Default
                                        usage
                                        exit;;
                        esac
                done
        else
                usage
                exit
        fi
}


# Write output and return result
theend() {
        echo $RESULT
        exit $EXIT_STATUS
}


#
## END FUNCTIONS
#

#############################################
#
## MAIN
#


# Handle command line options
doopts $@

# Verify that interface exists
if ! [ -L /sys/class/net/$INTERFACE ]; then
 RESULT="NETIO UNKNOWN - No interface $INTERFACE found"; EXIT_STATUS=3
 theend
fi 

# Detect Distribution
if [ -f /etc/redhat-release ]; then 
  ELVERSION=$(uname -r | sed "s/.*\.el\([1-9]*\)\.x86_64/\1/")
fi


# Do the do
if [ -n $ELVERSION ] && [ $ELVERSION -ge 7 ]; then
  # ifconfig output is different since EL7
  BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'RX packets' | awk '{print $5}'`
  BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'TX packets' | awk '{print $5}'`
else 
  BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f2 | $CUT -d" " -f1`
  BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f3 | $CUT -d" " -f1`
fi

RESULT="NETIO OK - $INTERFACE: RX=$BYTES_RX, TX=$BYTES_TX|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;;"

# Quit and return information and exit status
theend
