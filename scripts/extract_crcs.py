#!/usr/bin/env python3
"""Extrai a tabela __versions (CRC + nome) de um .ko e imprime simbolos selecionados.
Uso: extract_crcs.py <arquivo.ko> [filtro]
Compara CRCs de simbolos compartilhados entre seu .ko e um .ko stock do aparelho
para validar compatibilidade de modversions ANTES de flashar."""
import struct, sys, subprocess, re

ko = sys.argv[1]
pattern = sys.argv[2] if len(sys.argv) > 2 else ""

# Acha offset/tamanho da secao __versions via readelf -S
out = subprocess.run(["readelf", "-S", ko], capture_output=True, text=True).stdout
m = re.search(r"__versions\s+PROGBITS\s+[0-9a-f]+\s+([0-9a-f]+)\s+([0-9a-f]+)", out)
if not m:
    print("sem __versions"); sys.exit(1)
off, size = int(m.group(1), 16), int(m.group(2), 16)

data = open(ko, "rb").read()[off:off+size]
# struct modversion_info { unsigned long crc; char name[MODULE_NAME_LEN]; } MODULE_NAME_LEN=64
ENTRY = 8 + 64
n = 0
for i in range(0, len(data) - ENTRY + 1, ENTRY):
    crc = struct.unpack_from("<I", data, i)[0]
    raw = data[i+8:i+8+64].split(b"\0")[0]
    name = raw.decode("utf-8", "replace")
    if not name:
        continue
    if pattern in name or not pattern:
        print(f"{name}: 0x{crc:08x}")
        n += 1
print(f"--- total {n} simbolos (filtro '{pattern}')")
