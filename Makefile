# 对当前运行内核构建 bbrx 模块（必须安装对应内核头文件）
obj-m := tcp_bbrx.o
tcp_bbrx-y := src/tcp_bbrx.o
ccflags-y += -I$(src)
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
