ccflags-y := -D'pr_fmt(fmt)=KBUILD_MODNAME ": " fmt'
ccflags-$(CONFIG_WIREGUARD_DEBUG) += -DDEBUG
mywireguard-y := main.o
mywireguard-y += noise.o
mywireguard-y += device.o
mywireguard-y += peer.o
mywireguard-y += timers.o
mywireguard-y += queueing.o
mywireguard-y += send.o
mywireguard-y += receive.o
mywireguard-y += socket.o
mywireguard-y += peerlookup.o
mywireguard-y += allowedips.o
mywireguard-y += ratelimiter.o
mywireguard-y += cookie.o
mywireguard-y += netlink.o
obj-$(CONFIG_WIREGUARD) := mywireguard.o

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
