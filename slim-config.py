#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
slim-config.py — выключает в kernelconfig заведомо лишние для десктопа
Ryzen 5 9600X классы драйверов ДО компиляции (экономит время сборки и место).

Принцип: режем ТОЛЬКО драйверы по списку префиксов/точных имён.
НЕ трогаем: ядро, сеть (core), ext4/xfs/btrfs/f2fs/vfat/ntfs3, USB core,
Bluetooth-стек, Wi-Fi фреймворк + современные чипсеты (iwlwifi/mt76*/rtw88*/
rtw89*/ath11k/ath12k), GPU amdgpu/i915/xe, snd-hda/usb-audio, KVM(хост),
IOMMU, EDAC, crypto, PM/ACPI, CachyOS-специфику (CACHY/LTO/sched/HZ/MZEN*).

Использование:  python3 slim-config.py <путь-к-config>   (правка на месте)
Резервная копия создаётся как <файл>.orig
"""
import re, sys, shutil

PREFIXES = [
    # ---- гипервизоры / VM-гостевые драйверы (ваш ПК bare-metal!) ----
    'HYPERV', 'XEN_', 'VIRTIO_', 'VMWARE_', 'VMW_', 'VMXNET', 'PVSCSI',
    'DRM_VIRTIO_GPU', 'DRM_VMWGFX', 'DRM_HYPERV', 'DRM_BOCHS', 'DRM_QXL',
    'DRM_CIRRUS_QEMU', 'SERIAL_8250_XEN', 'FB_VGA16', 'FB_SIMPLE',
    'FB_VIRTUAL', 'VBOXFS',
    # ---- серверные NIC (Mellanox/QLogic/Brocade/Chelsio/Solarflare/Cavium...) ----
    'MLX4', 'MLX5', 'I40E', 'I40EVF', 'FM10KE', 'IGC', 'IXGB', 'IXGBEVF',
    'BNX2', 'BNX2X', 'TG3', 'SFC', 'CHELSIO', 'CXGB', 'CXGBV', 'ENIC',
    'BE2NET', 'BE2ISCSI', 'BNA', 'QED', 'QLA', 'LPFC', 'LIBFC', 'FCOE',
    'NE2K', 'LANCE', 'ATL1', 'ATL2', 'ATL1C', 'ATL1E', 'JME', 'R8712U',
    'ALACRYTECH', 'AQT100', 'CHINGLI', 'DE4X5', 'DEPCA', 'EL3', 'DLAPCI',
    'COPS', 'SUNDANCE', 'WINBOND_WS3', 'APRA', 'VLANCE', 'SGI_XP',
    'OCTEON', 'THUNDERX', 'MVMDIO', 'SFC_SIENA', 'AX88796B', 'ETH1394',
    'NET_VENDOR_3COM', 'NET_VENDOR_ALACRITECH', 'NET_VENDOR_AMAZON',
    'NET_VENDOR_AQUANTIA', 'NET_VENDOR_ARC', 'NET_VENDOR_BROCADE',
    'NET_VENDOR_CADENCE', 'NET_VENDOR_CAVIUM', 'NET_VENDOR_CHELSIO',
    'NET_VENDOR_CISCO', 'NET_VENDOR_DEC', 'NET_VENDOR_DLINK',
    'NET_VENDOR_EMULEX', 'NET_VENDOR_FARADAY', 'NET_VENDOR_HISILICON',
    'NET_VENDOR_HUAWEI', 'NET_VENDOR_IWISE', 'NET_VENDOR_LITEX',
    'NET_VENDOR_MARVELL', 'NET_VENDOR_MELLANOX', 'NET_VENDOR_MICREL',
    'NET_VENDOR_MICROCHIP', 'NET_VENDOR_MICROSEMI', 'NET_VENDOR_MYRI',
    'NET_VENDOR_NATSEMI', 'NET_VENDOR_NETERION', 'NET_VENDOR_NETRONOME',
    'NET_VENDOR_NVIDIA', 'NET_VENDOR_OKI', 'NET_VENDOR_PACKET_ENGINES',
    'NET_VENDOR_PENSANDO', 'NET_VENDOR_QLOGIC', 'NET_VENDOR_RDC',
    'NET_VENDOR_ROCKER', 'NET_VENDOR_SEALEVEL', 'NET_VENDOR_SOLARFLARE',
    'NET_VENDOR_STMICRO', 'NET_VENDOR_SUN', 'NET_VENDOR_TEHUTI',
    'NET_VENDOR_TI', 'NET_VENDOR_VIA', 'NET_VENDOR_WIZNET',
    'NET_VENDOR_SYNOPSYS',
    # ---- InfiniBand / RDMA ----
    'INFINIBAND', 'RDMA', 'IWARP', 'RPCRDMA', 'IB_',
    # ---- iSCSI offload / серверные HBA и RAID ----
    'ISCSI_BOOT', 'ISCSI_UIO',
    'MEGARAID', 'MPT2SAS', 'MPT3SAS', 'MPTBASE', 'MPI3', 'FUSION',
    'SMART2', 'SMART3', 'AACRAID', 'PM8001', 'PMATE', 'ADPT', 'IPR',
    'IPS', 'AIC79', 'AIC7XXX', 'DC395', 'DC390T', 'SYM53', 'NCR53C',
    'QLOGIC', 'CACHEFS', 'CPQARRA',
    'SCSI_FC', 'SCSI_QLA', 'SCSI_LPFC', 'SCSI_CXGB4_ISCSI',
    'SCSI_MPT', 'SCSI_SMART', 'SCSI_IPR', 'SCSI_ADV',
    # ---- eMMC/UFS/SDIO/Memstick host-контроллеры (десктоп: NVMe/SATA/USB) ----
    'MMC_', 'MEMSTICK', 'SSG', 'SR65',
    # ---- NVDIMM/DAX/pmem (серверная персистентная память) ----
    'NVDIMM', 'LIBNVDIMM', 'DAX_', 'ZONE_DEVICE', 'BLK_DEV_PMEM',
    'NSMEM', 'ND_', 'OF_PMEM', 'DEV_DAX',
    # ---- кластерные / сетевые / экзотические ФС ----
    'AFS_FS', 'OCFS2', 'GFS2', 'ORANGEFS', 'VXFS', 'QNX4', 'QNX6',
    'UFS_FS', 'OMFS_FS', 'MINIX_FS', 'SYSV_FS', 'ISDFS', 'AFFS',
    'ECRYPT_FS', 'DRBD', 'DLM', 'NILFS2', 'REISERFS', 'JFS_FS',
    'HFS_FS', 'HFSPLUS_FS', 'CRAMFS', 'PSTORE_BLK', 'ROMFS',
    # ---- CAN / hamradio / WPAN / NFC / IRDA / телефония ----
    'CAN_', 'HAMRADIO', 'AX25', 'IEEE802154', 'NFC', 'IRDA', 'PHONET',
    'CAIF', 'RXKAD', 'WWROCCO',
    # ---- PHY-драйверы медленных сегментных сетей (desktop Ethernet = R8169/I226) ----
    'MARVELL_10G_PHY', 'MICROSEMI_PHY', 'BROADCOM_PHY', 'ICPLUS_PHY',
    'MICREL_PHY', 'NXP_CBTX_PHY', 'XILINX_PHY', 'STE100XP', 'FIXED_PHY',
    'MDIO_BUS_MULTI', 'PHYLINK', 'PCS', 'NET_DSA', 'DSA',
    # ---- embedded/misc подсистемы ----
    'IIO_', 'EXTCON', 'RESET_CONTROLLER', 'REGULATOR', 'POWERCAP',
    'INTERCONNECT', 'GENERIC_PHY', 'GNSS', 'HWSPINLOCK', 'SSB', 'BCMA',
    'PCMCIA', 'IPACK', 'MCB', 'THS', 'SIOX', 'SLIMBUS', 'VOP', 'FPGA',
    'COMEDI', 'STAGING', 'ANDROID', 'ASHMEM', 'REMOTE_PROCESSOR',
    'RPMSG', 'REMOTPROC', 'MFD_', 'NVMEM_', 'SPI_', 'I3C_',
    'OSS',
    # ---- SoC-специфика ARM (на x86-конфиге почти нет, страховка) ----
    'ARCH_ROCKCHIP', 'ARCH_SUNXI', 'ARCH_TEGRA', 'ARCH_STM32',
    'ARCH_QCOM', 'ARCH_APPLE', 'MACH_', 'SOC_', 'TEGRA_', 'ROCKCHIP',
    'SUNXI', 'MESON', 'AMLOGIC', 'KEYSTONE', 'BCM2835', 'BCM2711',
    'TI_DR',
    # ---- non-x86 PCI host bridges ----
    'PCI_HOST_ECAM', 'PCI_XGENE', 'PCI_TEGRA', 'PCI_MVEBU',
    'PCI_LAYERSCAPE', 'PCI_IMX6', 'PCI_KEYSTONE', 'PCI_HYPERV',
    'PCIE_ALTERA', 'PCIE_DW_PLAT', 'PCIE_ROCKCHIP', 'PCIE_ZYNQ',
    'PCIE_XILINX', 'PCIE_MT2712', 'PCIE_ARTPEC6', 'PCIE_THUNDER',
    'PCIE_HI6220', 'PCIE_IXP4XX', 'PCIE_KIRKWOOD', 'PCIE_SOCFPGA',
    'PCIE_STI', 'PCIE_VF610',
    # ---- legacy framebuffer ----
    'FB_SAVAGE', 'FB_TRIDENT', 'FB_CYBER', 'FB_GEODE', 'FB_IMSTT',
    'FB_HECUBA', 'FB_AU1100', 'FB_CONTROL', 'FB_EFB', 'FB_VIA',
    'FB_ATARI', 'FB_COBALT', 'FB_P9100', 'FB_RETINA_Z3', 'FB_S1D',
    'FB_PM2FB', 'FB_ARC',
    # ---- legacy/embedded GPU без смысла на AM5 ----
    'DRM_RADEON', 'DRM_TDFX', 'DRM_VIA', 'DRM_GMA500', 'DRM_AST',
    'DRM_ARM', 'DRM_VC4', 'DRM_V3D', 'DRM_VGEM', 'DRM_XGI', 'DRM_PANEL',
    'DRM_LIMA', 'DRM_PANFROST', 'DRM_VIVANTE', 'DRM_ETNAVIV', 'DRM_HISI',
    'DRM_MCDE', 'DRM_MA35', 'DRM_VERISILICON', 'DRM_IMTDU',
    'DRM_GM7123UPT', 'DRM_COREBOOT', 'DRM_XEN', 'DRM_SHMOBILE',
    'DRM_RCAR', 'DRM_MEDIATEK', 'DRM_EXYNOS', 'DRM_OMAP', 'DRM_TI',
    'DRM_SUN6I', 'DRM_MESON', 'DRM_STI', 'DRM_ATMEL', 'DRM_INGENIC',
    'DRM_CDNS', 'DRM_FSL', 'DRM_IVPU', 'DRM_ACCEL', 'DRM_QAIC',
    'DRM_AMDXDNA', 'DRM_GUD', 'DRM_ASPEED', 'DRM_UDL',
    # ---- sound: SoC/ISA/legacy (snd-hda-core/intel/realteK + usb-audio ЖИВУТ) ----
    'SND_SOC', 'SND_USB_6FIRE', 'SND_FIREWIRE', 'SND_SPI', 'SND_PCMCIA',
    'SND_ES1', 'SND_SBAWE', 'SND_TRITON',
    'SND_VIA', 'SND_CS4', 'SND_AD1', 'SND_AZIA', 'SND_ALI', 'SND_OPL',
    'SND_YMF', 'SND_GUS', 'SND_ARM', 'SND_ATARI', 'SND_AU', 'SND_HAL2',
    'SND_FM8', 'SND_HARMONY', 'SND_MIPS', 'SND_SH', 'SND_SGI',
    'SND_SPARC', 'SND_SUN', 'SND_PPC', 'SND_VX', 'SND_ARC',
    # ---- Wi-Fi старых поколений (СОВРЕМЕННЫЕ iwlwifi/mt76/rtw8x/ath11k/ath12k НЕ трогаем) ----
    'ATH5K', 'ATH9K', 'ATH10K_AHB', 'CARL9170', 'RT2X00', 'RT73USB',
    'RT2800', 'ZD1211RW', 'P54', 'LIBERTAS', 'WL12', 'MWIFIEX', 'MWL8K',
    'BRCMFMAC', 'BRCMSMAC', 'RSI', 'TIDUP', 'IPW', 'WIMAX', 'WIRED',
    # ---- USB-периферия контроллеров SoC/gadget (USB core/xhci/ehci/uhci ЖИВУТ) ----
    'USB_GADGET', 'USB_TYPEC_MUX', 'USB_TYPEC_TCPC', 'USB_TYPEC_ALT_MODE_DP',
    'USB_APPLE', 'USB_CHAOSKEY', 'USB_DUMMY_HCD', 'USB_FOTG210',
    'USB_MUSB', 'USB_MV_U3D', 'USB_OCTEON', 'USB_QCOM', 'USB_ROCKCHIP',
    'USB_TEGRA', 'USB_XHCI_MTK', 'USB_XHCI_PCI_RENESAS', 'USB_CDNS3',
    'USB_DWC3_OF_SIMPLE', 'USB_ATM', 'USB_NET', 'USB_ISDN',
]

# точечные опции (точные имена)
OPTIONS = [
    'HYPERVISOR_GUEST', 'KVM_GUEST', 'PARAVIRT', 'PARAVIRT_SPINLOCKS',
    'X86_XEN',
]

# очистим список от случайного мусора (защита от опечаток при генерации)
PREFIXES = [p for p in PREFIXES if re.fullmatch(r'[A-Z0-9_]+', p)]

def main(path):
    shutil.copyfile(path, path + '.orig')
    lines = open(path).read().splitlines()
    out, off_n = [], 0
    for line in lines:
        m = re.match(r'^CONFIG_([A-Z0-9_]+)=[my]', line)
        if m:
            key = m.group(1)
            if any(key == p or key.startswith(p) for p in PREFIXES) or key in OPTIONS:
                out.append(f'# CONFIG_{key} is not set')
                off_n += 1
                continue
        out.append(line)
    open(path, 'w').write('\n'.join(out) + '\n')
    before = sum(1 for l in lines if re.search(r'=[my]$', l))
    print(f'Отключено опций драйверов: {off_n}')
    print(f'Включённых (=y/=m) было: {before}, стало: {before - off_n}')

if __name__ == '__main__':
    main(sys.argv[1])
