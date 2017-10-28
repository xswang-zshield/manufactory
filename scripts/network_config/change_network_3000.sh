#!/bin/bash

RULE_FILE="/etc/udev/rules.d/70-persistent-net.rules"
cat>$RULE_FILE<<EOF

# This file was automatically generated by the /lib/udev/write_net_rules
# program, run by the persistent-net-generator.rules rules file.
#
# You can modify it, as long as you keep each rule on a single
# line, and change only the value of the NAME= key.

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:02:00.0", NAME="eth0"

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:02:00.1", NAME="eth1"

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:83:00.0", NAME="eth2"

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:83:00.1", NAME="eth3"

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:83:00.2", NAME="eth4"

# PCI device 0x8086:0x1521 (igb)
SUBSYSTEM=="net", ACTION=="add", BUS=="pci", KERNELS=="0000:83:00.3", NAME="eth5"

EOF

