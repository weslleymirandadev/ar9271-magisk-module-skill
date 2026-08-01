---
name: magisk-kernel-modules
category: software-development
description: Compilar módulos .ko (ex ath9k_htc/AR9271) contra o kernel Android rodando e empacotar em módulo Magisk — sem rebuild do kernel inteiro. Funciona em qualquer aparelho com CONFIG_MODULES=y e /proc/config.gz.
---

# Módulos de kernel (.ko) via Magisk — sem rebuild do kernel

## Quando usar
- Quer um driver que NÃO está no kernel do aparelho (ex: AR9271/ath9k_htc, outros WiFi USB, CAN, USB serial)
- O kernel atual aceita módulos (CONFIG_MODULES=y)
- Não quer arriscar rebuild completo do kernel (bootloop com stubs MTK)

## Pré-requisitos
- Root + Magisk no aparelho
- adb (no WSL usar o do Windows: "/mnt/c/Program Files/platform-tools/adb.exe")
- Kernel source do aparelho (mesma versão do rodando)
- Toolchain: clang (kernel MTK 4.19 original usa Clang 11; clang 20 funciona com fix do -Werror)

## Passos resumidos
1. Checar CONFIG_MODULES=y no aparelho
2. Extrair config exata do kernel rodando (/proc/config.gz) — CUIDADO COM CRLF
3. Clonar source; achar commit do kernel rodando (sufixo -g<hash> do uname -r)
4. Copiar config, ligar driver como =m, remover selects problemáticos (MAC80211_LEDS!)
5. Ajustar vermagic (CONFIG_LOCALVERSION + remover .git)
6. modules_prepare + make M=<dir> modules
7. Comparar vermagic com .ko stock do aparelho
8. Testar AO VIVO com insmod (sem reboot)
9. Empacotar módulo Magisk (module.prop + service.sh + system/)
10. Instalar, reboot, verificar

## Detalhes

### 1. Checagens no aparelho
```
cat /proc/modules | head        # se listar módulos -> CONFIG_MODULES=y
zcat /proc/config.gz | grep CONFIG_MODULES
```
CONFIG_MODULES=y + /proc/config.gz existindo = caminho liberado. Sem /proc/config.gz fica difícil (config desconhecida -> CRCs do modversions não batem).

### 2. Extrair config (CUIDADO: CRLF!)
O adb do Windows manda \r\n. O Kconfig lê errado e o olddefconfig colapsa o config silenciosamente (5409 -> 1742 símbolos). Parece que "perdeu tudo" mas na verdade é o \r.
```
adb shell "zcat /proc/config.gz" > running.config
sed -i 's/\r$//' running.config     # OBRIGATÓRIO
```

### 3. Source + commit
```
uname -r   # ex: 4.19.188-g63320c935368
git clone --depth 1 -b <branch> <repo>
git fetch origin <hash-do-uname>   # se o commit ainda existir no repo
```
Se o commit não existir (repo rebaseado/force-push, aconteceu com LOST0113): OK, desde que a versão (4.19.188) bata — fixar vermagic manualmente (passo 5). CRCs de subsistemas estáveis (cfg80211/mac80211) tendem a bater entre commits próximos.

### 4. Config do build
```
cp running.config .config
./scripts/config --enable WLAN_VENDOR_ATH --module ATH9K_HTC
make ARCH=arm64 olddefconfig
```
⚠️ ARMADILHA #1 (select MAC80211_LEDS): o Kconfig do ath9k tem `select MAC80211_LEDS` (linhas ~24 e ~163 de drivers/net/wireless/ath/ath9k/Kconfig) que força CONFIG_MAC80211_LEDS=y. O kernel stock foi buildado com =n -> o .ko referencia __ieee80211_create_tpt_led_trigger e __ieee80211_get_radio_led_name que NÃO existem -> "Unknown symbol (err -2)" no insmod.
FIX: remover as linhas `select MAC80211_LEDS` do Kconfig, depois `./scripts/config --disable MAC80211_LEDS` + olddefconfig + syncconfig. Conferir: auto.conf NÃO pode ter CONFIG_MAC80211_LEDS=y.

⚠️ ARMADILHA #2 (olddefconfig liga coisa demais): SEMPRE comparar o .config novo com o running.config:
```
diff <(grep -E "^CONFIG_" running.config | sort) <(grep -E "^CONFIG_" .config | sort)
```
Só devem diferir: LOCALVERSION, CLANG_VERSION (toolchain) e os ATH9K/WLAN_VENDOR_ATH novos. Qualquer outra diferença = problema.

### 5. Vermagic (ARMADILHA #3)
O vermagic tem que ser IDÊNTICO ao do kernel rodando. Puxa um .ko stock de referência:
```
adb shell su -c "cp /vendor/lib/modules/wlan_drv_gen4m.ko /sdcard/"
adb pull /sdcard/wlan_drv_gen4m.ko
modinfo wlan_drv_gen4m.ko | grep vermagic
# ex: 4.19.188-g63320c935368 SMP preempt mod_unload modversions aarch64
```
O "+" no final aparece quando: árvore git suja OU sem tag exata OU LOCALVERSION env não setado. O scripts/setlocalversion (4.19) faz:
```
res="${res}${CONFIG_LOCALVERSION}${LOCALVERSION}"
if CONFIG_LOCALVERSION_AUTO=y: res+=$(scm_version)
else: se LOCALVERSION não setado e sem tag anotada exata: res+="+"
```
FIX que funcionou:
1. `./scripts/config --set-str LOCALVERSION "-g63320c935368"` (sufixo exato do uname)
2. `make ARCH=arm64 ... syncconfig` e conferir include/config/auto.conf
3. `mv .git .git.bak` (sem repo git, scm_version vazio -> sem "+")
4. build
5. `mv .git.bak .git` de volta
(Passar LOCALVERSION=... na linha de comando do make NÃO funciona — o make não exporta pro subprocesso do setlocalversion. Testado.)

### 6. Build
```
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
```
⚠️ ARMADILHA #4 (-Werror com clang novo): kernel 4.19 buildado com Clang 11; clang 20 quebra em código velho (ex: -Wunused-but-set-variable no ar9003_mci.c). Fix: remover "-Werror" do fim da linha ~977 do Makefile (KBUILD_CFLAGS).
```
make ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- M=drivers/net/wireless/ath modules
```
Se faltar include/generated/utsrelease.h após mexer no kernel.release:
`make ARCH=arm64 ... include/generated/utsrelease.h`

### 7. Verificação antes de flashar
- `modinfo *.ko | grep vermagic` == stock (sem "+")
- `nm ath9k_htc.ko | grep -i led` -> 0 símbolos
- CRC de símbolos compartilhados com o .ko stock: scripts/extract_crcs.py

### 8. Teste ao vivo (sem reboot)
```
adb push ath.ko ath9k_hw.ko ath9k_common.ko ath9k_htc.ko /data/local/tmp/
adb shell su -c "insmod /data/local/tmp/ath.ko && insmod /data/local/tmp/ath9k_hw.ko && insmod /data/local/tmp/ath9k_common.ko && insmod /data/local/tmp/ath9k_htc.ko"
```
ORDEM IMPORTANTE (dependências): ath -> ath9k_hw -> ath9k_common -> ath9k_htc
⚠️ ARMADILHA #5: "insmod: failed ... No such file or directory" com o arquivo existindo = símbolo desconhecido. Olhar dmesg!
Depois plugar o dongle USB e conferir: dmesg | grep -i ath9k, ip link | grep wlan.

### 9. Empacotar módulo Magisk
Estrutura:
```
kernel-hacking-features/
├── module.prop
├── service.sh
└── system/
    ├── lib/modules/*.ko
    └── vendor/firmware/htc_9271.fw
```
- module.prop: ver templates/module.prop
- service.sh: ver templates/service.sh (insmod na ordem + log pro Magisk)
- Firmware: htc_9271.fw NÃO está mais em lib/firmware/ath9k_htc/ no pacote Debian novo — está em usr/lib/firmware/htc_9271.fw. scripts/build.sh baixa do firmware-atheros do Debian (URL testada).
- build.sh NÃO vai pro celular — é ferramenta de build no WSL. O Magisk ignora.

### 10. Instalar
```
adb shell su -c "rm -rf /data/adb/modules/kernel-hacking-features"
adb push kernel-hacking-features /data/adb/modules/
adb reboot
```
Verificar no boot:
```
lsmod | grep ath9k
dmesg | grep -iE "ath9k|htc"    # espera: "usbcore: registered new interface driver ath9k_htc"
ls /vendor/firmware/htc_9271.fw
ip link | grep wlan
```

## Teste no Nethunter (Kali)
```
ip link | grep wlan    # wlan1 = AR9271 (wlan0 é a MTK interna)
bootkali                # entra no chroot
airmon-ng               # deve listar a interface Atheros
airmon-ng start wlan1
aireplay-ng --test mon0 # "Injection is working!" = monitor + injection OK
```

## Pitfalls (resumo)
1. CRLF no config puxado via adb -> colapsa o config no olddefconfig (sed 's/\r$//')
2. select MAC80211_LEDS no Kconfig do ath9k -> remover + desligar a opção
3. "+" no vermagic -> CONFIG_LOCALVERSION fixo + .git removido durante build
4. -Werror com clang novo -> remover do Makefile (linha ~977 KBUILD_CFLAGS)
5. Ordem dos insmod: ath -> ath9k_hw -> ath9k_common -> ath9k_htc
6. "No such file" do insmod com arquivo existindo = unknown symbol -> dmesg
7. olddefconfig liga opções que o stock tem off -> diff SEMPRE (passo 4)
8. Firmware Debian mudou de path: usr/lib/firmware/htc_9271.fw (não lib/firmware/ath9k_htc/)
9. Testar AO VIVO via insmod antes de rebootar — valida modversions na hora
10. **DOUBLE-FREE no ath9k_wmi_cmd (patch MTK/LOST0113!)**: o kernel do Moto G22 (LOST0113 lineage-20) tem um kfree_skb(skb) EXTRA no caminho de timeout do ath9k_wmi_cmd (wmi.c) que o upstream torvalds v4.19 NÃO tem. Quando o chip não responde ("Target is unresponsive" = timeout), o kfree_skb libera o skb que JÁ foi entregue ao URB (htc_send -> hif_usb_send_mgmt) e o callback do URB libera DE NOVO -> double-free/UAF -> corrupção de memória -> panic em código não relacionado (visto: sock_has_perm/SELinux) -> REBOOT ao plugar o dongle. Sintoma no pstore: "unix: Attempt to release alive unix socket" + kfree_skb chamado de ath9k_wmi_cmd. FIX: remover a linha kfree_skb(skb) do timeout path (comparar com raw.githubusercontent.com/torvalds/linux/v4.19/.../wmi.c)
11. **DEPOIS de rebuildar o .ko com fix, ATUALIZAR a pasta do módulo NO CELULAR**: testar via /data/local/tmp funciona, mas se o celular reiniciar, o service.sh carrega os .ko da pasta /data/adb/modules/... que podem ser os ANTIGOS -> bug volta. SEMPRE copiar os .ko novos pra pasta do módulo no device e conferir md5. Push direto pra /data/adb/modules dá "Permission denied" (SELinux/Magisk) — push pra /data/local/tmp e cp via su:
```
adb push ath.ko ath9k_hw.ko ath9k_common.ko ath9k_htc.ko /data/local/tmp/
adb shell su -c "cp /data/local/tmp/*.ko /data/adb/modules/<mod>/system/lib/modules/ && chmod 644 /data/adb/modules/<mod>/system/lib/modules/*.ko"
adb shell su -c "md5sum /data/adb/modules/<mod>/system/lib/modules/*.ko"   # conferir com os locais
```

## Debug de crash ao plugar o dongle (kernel panic/reboot)
Se o celular REINICIAR ao plugar o AR9271 = kernel panic. O trace está no pstore:
```
adb shell su -c "cat /sys/fs/pstore/console-ramoops-0" > pstore.txt
# procurar: "Kernel panic", "Call trace", "PC is at", "ath9k", "Attempt to release"
```
- WARNING "unix: Attempt to release alive unix socket" chamado de ath9k_wmi_cmd = double-free do skb (pitfall #10)
- Panic em sock_has_perm/SELinux logo depois = corrupção de memória vazando de outro subsistema (consequência, não causa)
- Verificar se o fix está no binário: aarch64-linux-gnu-objdump -d ath9k_htc.ko | awk '/<ath9k_wmi_cmd>:/,/^$/' | grep -c kfree_skb -> deve ser 1 (só o out: path), não 2

## Verificação final
- lsmod mostra ath9k_htc carregado após reboot
- dmesg sem "Unknown symbol"
- Plugar AR9271 -> dmesg "Firmware htc_9271.fw successfully loaded" + interface nova
- Nethunter: aireplay-ng --test = "Injection is working!"
