#!/bin/bash
###############################################################
# Monitoring plugin to check network I/O status
#
# Copyright 2007-2008 Ian Yates
# Copyright 2017-2020 Claudio Kuenzler
#
# See usage for command line switches
#
# History: 
# 2007-09-06 (i.yates@uea.ac.uk) - Created
# 2007-09-06 (i.yates@uea.ac.uk)
# 2008-11-27 (i.yates@uea.ac.uk) - Added GPLv3 licence
# 2017-01-27 (claudiokuenzler.com) - Added validation checks and compatibility with CentOS/RHEL 7
# 2018-06-05 (claudiokuenzler.com) - Added validation checks and compatibility with Ubuntu 18.04
# 2018-08-14 (claudiokuenzler.com) - Set LANG to English for correct parsing
# 2018-12-21 (claudiokuenzler.com) - Use /proc/net/dev instead of ifconfig (use -l for legacy)
# 2018-12-21 (claudiokuenzler.com) - Remove verbose mode (it was never implemented anyway)
# 2018-12-21 (claudiokuenzler.com) - Change default exit code to UNKNOWN
# 2018-12-21 (claudiokuenzler.com) - Remove dependency to (nagios|monitoring)-plugins-common
# 2019-06-21 (claudiokuenzler.com) - 1.4: Add interface error check (-e)
# 2020-02-12 (claudiokuenzler.com) - 1.5: Add interface drops to performance data, add tcp stats option (-t)
# 2020-02-13 (claudiokuenzler.com) - 1.5.1: Bugfix issue-6
# 2020-09-04 (claudiokuenzler.com) - 1.5.2: Bugfix issue-9
# 2020-09-04 (claudiokuenzler.com) - 1.6: Allow regular expression lookup for tcp statistics
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
###############################################################
VERSION="1.6.0"

IFCONFIG=/sbin/ifconfig
GREP=/bin/grep
CUT=/usr/bin/cut

INTERFACE=""
LEVEL_WARN="0"
LEVEL_CRIT="0"
RESULT=""
EXIT_STATUS=3
USE_IFCONFIG=false
IFERRORS=false
TCPSTATS=false
ERRORTMPFILE=/tmp/check_netio

export LANG=en_EN.UTF-8 # We need ifconfig in English
###############################################################
## FUNCTIONS

## Print usage
usage() {
  echo " check_netio $VERSION - Monitoring plugin to check network interface and I/O"
  echo ""
  echo " USAGE: check_netio.sh -i INTERFACE [-l] [-e] [-t] [-r] [-h]"
  echo ""
  echo "           -i  Interface to check (e.g. eth0)"
  echo "           -l  Use legacy mode (use ifconfig command)"
  echo "           -e  Enable check of interface errors"
  echo "           -t  Enable tcp statistics (system-wide, not limited to chosen interface)"
  echo "           -r  Comma-separated list of strings for regular expression lookup in tcp statistics (in combination with -t)"
  echo "           -h  Show this page"
  echo ""
}

## Process command line options
doopts() {
if ( `test 0 -lt $#` ); then
  while getopts i:letr:h myarg "$@"; do
    case $myarg in
    h|\?) usage; exit;;
    i) INTERFACE=$OPTARG;;
    l) USE_IFCONFIG=true;;
    e) IFERRORS=true;;
    r) REGEX=$OPTARG;;
    t) TCPSTATS=true;;
    *) usage; exit;;
    esac
  done
else
  usage; exit
fi
}

# Write output and return result
theend() {
  echo $RESULT
  exit $EXIT_STATUS
}
## END FUNCTIONS
###############################################################
## MAIN

# Handle command line options
doopts $@

# Get the full output from /proc/net/dev
INTERFACES_FULL="`cat /proc/net/dev`"

# Verify that interface exists
if ! [ -L /sys/class/net/$INTERFACE ]; then
 RESULT="NETIO UNKNOWN - No interface $INTERFACE found"; EXIT_STATUS=3
 theend
fi

if [ $USE_IFCONFIG = true ]; then
  # Get the full ifconfig output from the selected interface
  IFCONFIG_FULL=`$IFCONFIG $INTERFACE`
fi

if [ $TCPSTATS = true ]; then
  # Collect netstat stats
  NETSTAT_FULL=`cat /proc/net/netstat`
fi

# For legacy reasons we keep this information here:
# Check what kind of ifconfig response we get. Here are a few examples.
#
# Typical Linux -2017:
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

if [ $USE_IFCONFIG = true ]; then 
  # So user dediced to use ifconfig
  if [[ -n $(echo $IFCONFIG_FULL | grep "RX packets:") ]]; then
	# This is the old ifconfig output
	BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f2 | $CUT -d" " -f1`
  	BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $CUT -d":" -f3 | $CUT -d" " -f1`
  else
	# This is the new ifconfig output 2017 and newer
	BYTES_RX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'RX packets' | awk '{print $5}'`
	BYTES_TX=`$IFCONFIG $INTERFACE | $GREP 'bytes' | $GREP 'TX packets' | awk '{print $5}'`
  fi
else
  # Hurray, we directly parse the /proc/net/dev output and save time
  BYTES_RX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$2}") 
  ERRORS_RX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$4}") 
  DROPS_RX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$5}") 
  BYTES_TX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$10}") 
  ERRORS_TX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$12}") 
  DROPS_TX=$( echo "$INTERFACES_FULL" | awk "/${INTERFACE}:/ {print \$13}") 
fi

# Handle netstat stats
if [ $TCPSTATS = true ]; then
  IFS=' '
  read -r -a key <<< `echo $NETSTAT_FULL|sed -ne "1p"|$CUT -d ' ' -f 1 --complement`
  read -r -a value <<< `echo $NETSTAT_FULL|sed -ne "2p"|$CUT -d ' ' -f 1 --complement`
  i=0
  for key in ${key[*]}; do
         if [[ -n ${REGEX} ]]; then
           declare -a regex_list=($(echo "$REGEX" | sed 's/,/ /g'))
           shopt -s nocasematch
           for regex in ${regex_list[*]}; do
             if [[ ${key} =~ "${regex}" ]]; then
	       tcpperfdata[$i]="${key[$i]}=${value[$i]};;;; "
             fi
           done
         else
	   tcpperfdata[$i]="${key[$i]}=${value[$i]};;;; "
         fi
	 let i++
 done
 else tcpperfdata=""
fi

# Handle interface errors
if [ $IFERRORS = true ]; then
  if [ -f ${ERRORTMPFILE}_${INTERFACE} ]; then 
    # Oh, we already saw errors before, compare values
    PREVIOUS_ERRORS_RX=$(tail -n 2 ${ERRORTMPFILE}_${INTERFACE} | awk "/ERRORS_RX/ {print \$3}")
    PREVIOUS_ERRORS_TX=$(tail -n 2 ${ERRORTMPFILE}_${INTERFACE} | awk "/ERRORS_TX/ {print \$3}")
    if [[ $ERRORS_RX -gt $PREVIOUS_ERRORS_RX || $ERRORS_TX -gt $PREVIOUS_ERRORS_TX ]]; then 
      echo "$(date +%s) ERRORS_RX $ERRORS_RX" >> ${ERRORTMPFILE}_${INTERFACE}
      echo "$(date +%s) ERRORS_TX $ERRORS_TX" >> ${ERRORTMPFILE}_${INTERFACE}
      RESULT="NETIO WARNING - Errors on $INTERFACE: $ERRORS_RX Receive errors (previous check: $PREVIOUS_ERRORS_RX), $ERRORS_TX Transmit errors (previous check: $PREVIOUS_ERRORS_TX)|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;; NET_${INTERFACE}_ERR_RX=${ERRORS_RX};;;; NET_${INTERFACE}_ERR_TX=${ERRORS_TX};;;; NET_${INTERFACE}_DROP_RX=${DROPS_RX};;;; NET_${INTERFACE}_DROP_TX=${DROPS_TX};;;; ${tcpperfdata[*]}"
      EXIT_STATUS=1
    else
      # output ok with hint that no change in error count
      RESULT="NETIO OK - $INTERFACE: Receive $BYTES_RX Bytes, Transmit $BYTES_TX Bytes - Hint: Previously detected errors (Receive: $PREVIOUS_ERRORS_RX, Transmit: $PREVIOUS_ERRORS_TX) but no change since last check|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;; NET_${INTERFACE}_ERR_RX=${ERRORS_RX};;;; NET_${INTERFACE}_ERR_TX=${ERRORS_TX};;;; NET_${INTERFACE}_DROP_RX=${DROPS_RX};;;; NET_${INTERFACE}_DROP_TX=${DROPS_TX};;;; ${tcpperfdata[*]}"
      EXIT_STATUS=0
    fi
  else # Check if we got errors
    if [[ $ERRORS_RX -gt 0 || $ERRORS_TX -gt 0 ]]; then
      echo "$(date +%s) ERRORS_RX $ERRORS_RX" >> ${ERRORTMPFILE}_${INTERFACE}
      echo "$(date +%s) ERRORS_TX $ERRORS_TX" >> ${ERRORTMPFILE}_${INTERFACE}
      RESULT="NETIO WARNING - Errors on $INTERFACE: $ERRORS_RX Receive errors, $ERRORS_TX Transmit errors|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;; NET_${INTERFACE}_ERR_RX=${ERRORS_RX};;;; NET_${INTERFACE}_ERR_TX=${ERRORS_TX};;;; NET_${INTERFACE}_DROP_RX=${DROPS_RX};;;; NET_${INTERFACE}_DROP_TX=${DROPS_TX};;;; ${tcpperfdata[*]}"
      EXIT_STATUS=1
    else
      RESULT="NETIO OK - $INTERFACE: Receive $BYTES_RX Bytes, Transmit $BYTES_TX Bytes|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;; NET_${INTERFACE}_ERR_RX=${ERRORS_RX};;;; NET_${INTERFACE}_ERR_TX=${ERRORS_TX};;;; NET_${INTERFACE}_DROP_RX=${DROPS_RX};;;; NET_${INTERFACE}_DROP_TX=${DROPS_TX};;;; ${tcpperfdata[*]}"
      EXIT_STATUS=0
    fi
  fi
else # No error handling, just output the stats
  RESULT="NETIO OK - $INTERFACE: Receive $BYTES_RX Bytes, Transmit $BYTES_TX Bytes|NET_${INTERFACE}_RX=${BYTES_RX}B;;;; NET_${INTERFACE}_TX=${BYTES_TX}B;;;; NET_${INTERFACE}_ERR_RX=${ERRORS_RX};;;; NET_${INTERFACE}_ERR_TX=${ERRORS_TX};;;; NET_${INTERFACE}_DROP_RX=${DROPS_RX};;;; NET_${INTERFACE}_DROP_TX=${DROPS_TX};;;; ${tcpperfdata[*]}"
  EXIT_STATUS=0
fi

# Quit and return information and exit status
theend
