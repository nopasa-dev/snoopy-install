#connect
#sudo screen /dev/ttyACM0 115200
#login as root
#nmcli device wifi connect 'ay23bbmus' password 'mus1kpus1k' ifname wlan0

#once connected to wifi

#run

#wget -q -O - http://install.nopasa.com | bash

#inside script will:

#download and install snoopy

apt-get update -y
apt-get upgrade -y

apt-get install monit hostapd dnsmasq -

wget http://.deb

dpkg -i snoopy_1.1.12_arm.deb -y

#restart things