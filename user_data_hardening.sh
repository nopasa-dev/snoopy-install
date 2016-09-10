#!/bin/bash
# user-data-hardening.sh
# Authors: Cody Bunch (bunchc@gmail.com)
#
# Script intended to be supplied as userdata to a cloud of some flavor.
# Enables some sane sysctl defaults, turns up iptables, and
# installs a HIDS / NIDS package

# Supply your email here
email_address="userdata@mailinator.com"

# Other things worth verifying / changing:
IPTABLES=/sbin/iptables
IP6TABLES=/sbin/ip6tables
MODPROBE=/sbin/modprobe

INT_INTF=eth1
EXT_INTF=eth0
INT_NET=$(ifconfig $INT_INTF | awk '/inet addr/ {split ($2,A,":"); print A[2]}')

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get install -y iptables

# Sysctl
sudo echo "
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0 
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0 
net.ipv6.conf.default.accept_redirects = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_all = 1
" >> /etc/sysctl.conf

sudo sysctl -p

# Firewall
# Modified from http://www.cipherdyne.org/LinuxFirewalls/ch01/

### flush existing rules and set chain policy setting to DROP
echo "[+] Flushing existing iptables rules..."
$IPTABLES -F
$IPTABLES -F -t nat
$IPTABLES -X
$IPTABLES -P INPUT DROP
$IPTABLES -P FORWARD DROP

### this policy does not handle IPv6 traffic except to drop it.
#
echo "[+] Disabling IPv6 traffic..."
$IP6TABLES -P INPUT DROP
$IP6TABLES -P OUTPUT DROP
$IP6TABLES -P FORWARD DROP

### load connection-tracking modules
#
$MODPROBE ip_conntrack
$MODPROBE iptable_nat
$MODPROBE ip_conntrack_ftp
$MODPROBE ip_nat_ftp

###### INPUT chain ######
#
echo "[+] Setting up INPUT chain..."

### state tracking rules
$IPTABLES -A INPUT -m conntrack --ctstate INVALID -j LOG --log-prefix "DROP INVALID " --log-ip-options --log-tcp-options
$IPTABLES -A INPUT -m conntrack --ctstate INVALID -j DROP
$IPTABLES -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

### anti-spoofing rules
$IPTABLES -A INPUT -i $INT_INTF ! -s $INT_NET -j LOG --log-prefix "SPOOFED PKT "
$IPTABLES -A INPUT -i $INT_INTF ! -s $INT_NET -j DROP

### ACCEPT rules
$IPTABLES -A INPUT -i $INT_INTF -p tcp -s $INT_NET --dport 22 -m conntrack --ctstate NEW -j ACCEPT
$IPTABLES -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

### default INPUT LOG rule
$IPTABLES -A INPUT ! -i lo -j LOG --log-prefix "DROP " --log-ip-options --log-tcp-options

### make sure that loopback traffic is accepted
$IPTABLES -A INPUT -i lo -j ACCEPT

###### OUTPUT chain ######
#
echo "[+] Setting up OUTPUT chain..."

### state tracking rules
$IPTABLES -A OUTPUT -m conntrack --ctstate INVALID -j LOG --log-prefix "DROP INVALID " --log-ip-options --log-tcp-options
$IPTABLES -A OUTPUT -m conntrack --ctstate INVALID -j DROP
$IPTABLES -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

### default OUTPUT LOG rule
$IPTABLES -A OUTPUT ! -o lo -j LOG --log-prefix "DROP " --log-ip-options --log-tcp-options

### make sure that loopback traffic is accepted
$IPTABLES -A OUTPUT -o lo -j ACCEPT

###### FORWARD chain ######
#
echo "[+] Setting up FORWARD chain..."

### state tracking rules
$IPTABLES -A FORWARD -m conntrack --ctstate INVALID -j LOG --log-prefix "DROP INVALID " --log-ip-options --log-tcp-options
$IPTABLES -A FORWARD -m conntrack --ctstate INVALID -j DROP
$IPTABLES -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

### anti-spoofing rules
$IPTABLES -A FORWARD -i $INT_INTF ! -s $INT_NET -j LOG --log-prefix "SPOOFED PKT "
$IPTABLES -A FORWARD -i $INT_INTF ! -s $INT_NET -j DROP

# Fail2Ban
sudo apt-get install -y fail2ban

# Postfix
$hostname = `hostname -f`
cat > /var/cache/debconf/postfix.preseed <<EOF
postfix postfix/chattr  boolean false
postfix postfix/mailname    string  $hostname
postfix postfix/main_mailer_type    select  Internet Site
EOF

sudo debconf-set-selections /var/cache/debconf/postfix.preseed
sudo apt-get install -f postfix

# NIDS - psad
sudo apt-get install -y psad

# HIDS - Aide
sudo apt-get install -y aide
sudo aideinit
sudo aide -u

# Log Reporting
sudo apt-get install -y logwatch

sudo echo "
/usr/sbin/logwatch --output mail --mailto ${email_address} --detail high
" >> /etc/cron.daily/00logwatch