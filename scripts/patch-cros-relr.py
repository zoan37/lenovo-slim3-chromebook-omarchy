#!/usr/bin/env python3
"""Make ChromeOS libraries (libmali, libminigbm, ...) loadable by upstream glibc (>= 2.36).

ChromeOS links its libraries with RELR relocations (DT_RELR) but without the GLIBC_ABI_DT_RELR version dependency that
upstream glibc requires for them ("DT_RELR without GLIBC_ABI_DT_RELR dependency"); ChromeOS's glibc doesn't check.
This adds that version requirement under libc.so.6 with LIEF and writes a new file; the input is never modified.
The vendor binary is not redistributed: run this on the copy taken from the machine's own ChromeOS partition.

Usage: patch-cros-relr.py <in .so> <out .so>   (needs: pip install lief)
"""
import sys
import lief

def elf_hash(name: str) -> int:
    h = 0
    for c in name.encode():
        h = (h << 4) + c
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g
    return h & 0xFFFFFFFF

src, dst = sys.argv[1], sys.argv[2]
b = lief.ELF.parse(src)
assert b.has(lief.ELF.DynamicEntry.TAG.RELR), "no DT_RELR, nothing to do"
reqs = {r.name: r for r in b.symbols_version_requirement}
libc = reqs["libc.so.6"]
if any(a.name == "GLIBC_ABI_DT_RELR" for a in libc.get_auxiliary_symbols()):
    sys.exit("already has GLIBC_ABI_DT_RELR")
used = {a.other for r in reqs.values() for a in r.get_auxiliary_symbols()}
aux = lief.ELF.SymbolVersionAuxRequirement()
aux.name = "GLIBC_ABI_DT_RELR"
aux.hash = elf_hash(aux.name)
aux.flags = 0
aux.other = max(used) + 1
libc.add_auxiliary_requirement(aux)
b.write(dst)
check = lief.ELF.parse(dst)
print({r.name: [(a.name, a.other, hex(a.hash)) for a in r.get_auxiliary_symbols()] for r in check.symbols_version_requirement})
