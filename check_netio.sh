#!/bin/bash
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
# Updated: 2018-06-05 (www.claudiokuenzler.com) - Added validation checks and compatibility with Ubuntu 18.04
# Updated: 2018-08-14 (www.claudiokuenzler.com) - Set LC_LANG to English for correct persing
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

export LANG=en_EN.UTF-8 # We need ifconfig in English

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

# Get the full ifconfig output from the selected interface
IFCONFIG_FULL=`$IFCONFIG $INTERFACE`

# Check what kind of ifconfig response we get. Here are a few examples.
#
# Typical Linux 20?? - 2017:
#eth0      Link encap:Ethernet  HWaddr 00:50:56:99:35:34
#          inet addr:10.161.204.204  Bcast:10.161.204.255  Mask:255.255.255.0
#          inet6 addr: fe80::250:56ff:fe99:3534/64 Scope:Link
#          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
#          RX packets:13244146360 errors:0 dropped:47729 overruns:0 frame:0
#          TX packets:12690444622 errors:0 dropped:0 overruns:0 carrier:0
#          collisions:0 txqueuelen:1000
#          RX bytes:10473813937684 (10.4 TB)  TX bytes:1956197200532 (1.9 TB)
#
# Starting in 2017, first seen in RHEL/Centos 7:
#eno16777984: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
#        inet 10.162.215.71  netmask 255.255.255.0  broadcast 10.162.215.255
#        inet6 fe80::250:56ff:fe8d:5c15  prefixlen 64  scopeid 0x20<link>
#        ether 00:50:56:8d:5c:15  txqueuelen 1000  (Ethernet)
#        RX packets 1419523582  bytes 5884437221627 (5.3 TiB)
#        RX errors 0  dropped 130904  overruns 0  frame 0
#        TX packets 771824547  bytes 252382597591 (235.0 GiB)
#        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

if [[ -n $(echo $IFCONFIG_FULL | grep "RX packets:") ]]; then
	# This is the old ifconfig output
	BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f2 | $CUT -d" " -f1`
  	BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f3 | $CUT -d" " -f1`
else
	# This is the new ifconfig output 2017 and newer
	BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'RX packets' | awk '{print $5}'`
	BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'TX packets' | awk '{print $5}'`
fi

RESULT="NETIO OK - $INTERFACE: RX=$BYTES_RX, TX=$BYTES_TX|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;;"

# Quit and return information and exit status
theend
