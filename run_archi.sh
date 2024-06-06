#!/usr/bin/env bash
# create a temporary folder for the process
mkdir -p /tmp/.tmp

# write the pid of the main process (that should be a network and mount namespace)
# may be useful if we want to nsenter later
echo $$ > /tmp/.tmp/pid

# isolate all temporary files from the actual computer
# we use /tmp/.tmp so we can share files between namespaces
# and main computer by using /tmp
mount -t tmpfs none /tmp/.tmp

# create a folder to make named namespaces
mkdir /tmp/.tmp/ns
mount --bind /tmp/.tmp/ns /tmp/.tmp/ns # i'm not sure it's needed
mount --make-private /tmp/.tmp/ns # make it private

# create the files for all network namespaces
touch /tmp/.tmp/ns/{mntrouter,netrouter,utsrouter}
touch /tmp/.tmp/ns/{mntbox,netbox,utsbox}
touch /tmp/.tmp/ns/{mntvpn,netvpn,utsvpn}
touch /tmp/.tmp/ns/{mntdest,netdest,utsdest}
touch /tmp/.tmp/ns/{mntclient,netclient,utsclient}

# create the namespaces
unshare --net=/tmp/.tmp/ns/netrouter --mount=/tmp/.tmp/ns/mntrouter --uts=/tmp/.tmp/ns/utsrouter hostname router
unshare --net=/tmp/.tmp/ns/netbox --mount=/tmp/.tmp/ns/mntbox --uts=/tmp/.tmp/ns/utsbox hostname box
unshare --net=/tmp/.tmp/ns/netvpn --mount=/tmp/.tmp/ns/mntvpn --uts=/tmp/.tmp/ns/utsvpn hostname vpn
unshare --net=/tmp/.tmp/ns/netdest --mount=/tmp/.tmp/ns/mntdest --uts=/tmp/.tmp/ns/utsdest hostname dest
unshare --net=/tmp/.tmp/ns/netclient --mount=/tmp/.tmp/ns/mntclient --uts=/tmp/.tmp/ns/utsclient hostname client

# create the veth links
ip link add ethrouter netns /tmp/.tmp/ns/netbox type veth peer name ethbox netns /tmp/.tmp/ns/netrouter
ip link add eth0 netns /tmp/.tmp/ns/netvpn type veth peer name ethvpn netns /tmp/.tmp/ns/netrouter
ip link add eth0 netns /tmp/.tmp/ns/netdest type veth peer name ethdest netns /tmp/.tmp/ns/netrouter
ip link add eth0 netns /tmp/.tmp/ns/netclient type veth peer name ethclient netns /tmp/.tmp/ns/netbox

# box interfaces config
nsenter --net=/tmp/.tmp/ns/netbox ip link set up dev lo
nsenter --net=/tmp/.tmp/ns/netbox ip link set up dev ethrouter
nsenter --net=/tmp/.tmp/ns/netbox ip link set up dev ethclient
nsenter --net=/tmp/.tmp/ns/netbox ip a a 10.10.1.2/24 dev ethrouter
nsenter --net=/tmp/.tmp/ns/netbox ip a a 192.168.0.1/24 dev ethclient
nsenter --net=/tmp/.tmp/ns/netbox ip r a default via 10.10.1.1

# vpn interfaces config
nsenter --net=/tmp/.tmp/ns/netvpn ip link set up dev lo
nsenter --net=/tmp/.tmp/ns/netvpn ip link set up dev eth0
nsenter --net=/tmp/.tmp/ns/netvpn ip a a 10.10.2.2/24 dev eth0
nsenter --net=/tmp/.tmp/ns/netvpn ip r a default via 10.10.2.1

# dest interfaces config
nsenter --net=/tmp/.tmp/ns/netdest ip link set up dev lo
nsenter --net=/tmp/.tmp/ns/netdest ip link set up dev eth0
nsenter --net=/tmp/.tmp/ns/netdest ip a a 10.10.3.2/24 dev eth0
nsenter --net=/tmp/.tmp/ns/netdest ip r a default via 10.10.3.1

# router interfaces config
nsenter --net=/tmp/.tmp/ns/netrouter ip link set up dev lo
nsenter --net=/tmp/.tmp/ns/netrouter ip link set up dev ethbox
nsenter --net=/tmp/.tmp/ns/netrouter ip link set up dev ethvpn
nsenter --net=/tmp/.tmp/ns/netrouter ip link set up dev ethdest
nsenter --net=/tmp/.tmp/ns/netrouter ip a a 10.10.1.1/24 dev ethbox
nsenter --net=/tmp/.tmp/ns/netrouter ip a a 10.10.2.1/24 dev ethvpn
nsenter --net=/tmp/.tmp/ns/netrouter ip a a 10.10.3.1/24 dev ethdest

# client interfaces config
nsenter --net=/tmp/.tmp/ns/netclient ip link set up dev lo
nsenter --net=/tmp/.tmp/ns/netclient ip link set up dev eth0
nsenter --net=/tmp/.tmp/ns/netclient ip a a 192.168.0.2/24 dev eth0
nsenter --net=/tmp/.tmp/ns/netclient ip r a default via 192.168.0.1

# setup NAT on box
nsenter --net=/tmp/.tmp/ns/netbox iptables -t nat -A POSTROUTING -o ethrouter -j MASQUERADE

# disable direct connexion between box and dest
nsenter --net=/tmp/.tmp/ns/netrouter iptables -A FORWARD -s 10.10.1.0/24 -d 10.10.3.0/24 -j DROP

##### LANCER WIREGUARD SUR LE CLIENT ET LE VPN #####

# get write access in /var/run for the mount namespaces of vpn and client
# needed by wireguard-go to create /var/run/wireguard folder
nsenter --mount=/tmp/.tmp/ns/mntclient mkdir -p /tmp/.tmp/var/run
nsenter --mount=/tmp/.tmp/ns/mntclient mount -t tmpfs none /tmp/.tmp/var/run
nsenter --mount=/tmp/.tmp/ns/mntclient bash -c "for d in /var/run/*/; do mkdir -p /tmp/.tmp\$d; mount --rbind \$d /tmp/.tmp\$d; done"
nsenter --mount=/tmp/.tmp/ns/mntclient mount --rbind /tmp/.tmp/var/run/ /var/run

nsenter --mount=/tmp/.tmp/ns/mntvpn mkdir -p /tmp/.tmp/var/run
nsenter --mount=/tmp/.tmp/ns/mntvpn mount -t tmpfs none /tmp/.tmp/var/run
nsenter --mount=/tmp/.tmp/ns/mntvpn bash -c "for d in /var/run/*/; do mkdir -p /tmp/.tmp\$d; mount --rbind \$d /tmp/.tmp\$d; done"
nsenter --mount=/tmp/.tmp/ns/mntvpn mount --rbind /tmp/.tmp/var/run/ /var/run

# generate private keys for wireguard
wg genkey > /tmp/.tmp/privatevpn
wg genkey > /tmp/.tmp/privateclient

# setup wireguard-go server
nsenter --mount=/tmp/.tmp/ns/mntvpn --net=/tmp/.tmp/ns/netvpn wireguard-go wg0
nsenter --mount=/tmp/.tmp/ns/mntvpn --net=/tmp/.tmp/ns/netvpn wg set wg0 private-key /tmp/.tmp/privatevpn listen-port 38000 # ne pas oublier de setup la private-key, on utilise ensuite la public-key pour setup le peer
nsenter --mount=/tmp/.tmp/ns/mntvpn --net=/tmp/.tmp/ns/netvpn ip a a 192.168.1.1/24 dev wg0
nsenter --mount=/tmp/.tmp/ns/mntvpn --net=/tmp/.tmp/ns/netvpn wg set wg0 peer $(wg pubkey < /tmp/.tmp/privateclient) allowed-ips 0.0.0.0/0 endpoint 192.168.0.2:38001 # le endpoint c'est l'ip publique de la machine cliente pour la contacter et le port sur lequel tourne wireguard-go
nsenter --mount=/tmp/.tmp/ns/mntvpn --net=/tmp/.tmp/ns/netvpn ip link set dev wg0 up

# ne pas oublier de config le SNAT pour accéder à l'extérieur en tant que le vpn
nsenter --net=/tmp/.tmp/ns/netvpn iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to 10.10.2.2  # masquerade marche pas car choisit pas la bonne ip sortante

# setup wireguard-go client
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient wireguard-go wg0
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient wg set wg0 private-key /tmp/.tmp/privateclient listen-port 38001 # ne pas oublier de setup la private-key, on utilise ensuite la public-key pour setup le peer
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient ip a a 192.168.1.2/24 dev wg0
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient wg set wg0 peer $(wg pubkey < /tmp/.tmp/privatevpn) allowed-ips 0.0.0.0/0 endpoint 10.10.2.2:38000 # le endpoint c'est l'ip publique de la machine cliente pour la contacter et le port sur lequel tourne wireguard-go
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient ip link set dev wg0 up

# on ajoute la route pour faire passer le traffic par le vpn et bypass le blocage
nsenter --mount=/tmp/.tmp/ns/mntclient --net=/tmp/.tmp/ns/netclient ip r a 10.10.3.0/24 via 192.168.1.1


##### CREER UN ALIAS POUR SE SIMPLIFIER LA VIE ####
entermachine () {
  nsenter --mount=/tmp/.tmp/ns/mnt$1 --net=/tmp/.tmp/ns/net$1 --uts=/tmp/.tmp/ns/uts$1
}

# export entermachine so I can call it in the inner bash process
export -f entermachine

bash
