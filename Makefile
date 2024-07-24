ccflags-y := -D'pr_fmt(fmt)=KBUILD_MODNAME ": " fmt'
ccflags-$(CONFIG_WIREGUARD_DEBUG) += -DDEBUG
mywireguard_noencrypt-y := main.o
mywireguard_noencrypt-y += noise.o
mywireguard_noencrypt-y += device.o
mywireguard_noencrypt-y += peer.o
mywireguard_noencrypt-y += timers.o
mywireguard_noencrypt-y += queueing.o
mywireguard_noencrypt-y += send.o
mywireguard_noencrypt-y += receive.o
mywireguard_noencrypt-y += socket.o
mywireguard_noencrypt-y += peerlookup.o
mywireguard_noencrypt-y += allowedips.o
mywireguard_noencrypt-y += ratelimiter.o
mywireguard_noencrypt-y += cookie.o
mywireguard_noencrypt-y += netlink.o
obj-$(CONFIG_WIREGUARD) := mywireguard_noencrypt.o

# obj-m += main.o

KERN_DIR=/lib/modules/$(shell uname -r)/build/

host:
	make -C $(KERN_DIR) M=$(PWD) modules
install:
	make -C $(KERN_DIR) M=$(PWD) modules_install
clean:
	make -C $(KERN_DIR) M=$(PWD) clean
help:
	make -C $(KERN_DIR) M=$(PWD) help
