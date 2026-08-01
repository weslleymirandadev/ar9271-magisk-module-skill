#!/system/bin/sh
# Carrega os modulos do AR9271 (ath9k_htc) na ordem correta de dependencia
MODDIR=${0%/*}
KO_DIR="$MODDIR/system/lib/modules"

insmod "$KO_DIR/ath.ko" 2>/dev/null
insmod "$KO_DIR/ath9k_hw.ko" 2>/dev/null
insmod "$KO_DIR/ath9k_common.ko" 2>/dev/null
insmod "$KO_DIR/ath9k_htc.ko" 2>/dev/null

if ls /sys/class/net/ | grep -q wlan; then
    echo "[kernel-hacking] ath9k_htc carregado OK"
    ls /sys/class/net/
else
    echo "[kernel-hacking] ATENCAO: interface wlan nao subiu"
    dmesg | grep -i ath9k | tail -5
fi
