#!/usr/bin/env bash
# ============================================================================
# zen5-patches.sh — добавляет поддержку AMD Zen 5 (znver5) в PKGBUILD'ы linux-cachyos
#
# Зачем это нужно:
#   В апстриме linux-cachyos переменная _processor_opt понимает только
#   zen4 / GENERIC_V1..V4 / NATIVE / generic. Ryzen 5 9600X — это Zen 5,
#   который требует znver5 (GCC >= 14 / Clang >= 18). Кроме того, CI-секция
#   апстримного PKGBUILD принудительно переключает сборку на -Os
#   (CC_OPTIMIZE_FOR_SIZE), из-за чего «оптимизация под процессор» в GitHub
#   Actions теряется. Этот скрипт чинит оба момента.
#
# Что делает (только text-replace, идемпотентно):
#   1. case "$MARCH": добавляются ветки ZEN5 -> CONFIG_MZEN5 и
#      GENERIC_V5 -> CONFIG_GENERIC_CPU + X86_USE_3DNOW... (x86-v5)
#   2. все "-d MZEN4" дополняются "-d MZEN5", чтобы конфиги не конфликтовали
#   3. отключается CI-понижение оптимизации до -Os (сохраняем -O3/znver5)
#   4. включается CONFIG_CACHY (cachy sauce tunables) даже в CI
#
# Запуск: ./zen5-patches.sh [каталог-репозитория]   (по умолчанию .)
# ============================================================================
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

mapfile -t PKGBUILDS < <(find . -name PKGBUILD | sort)
if [ "${#PKGBUILDS[@]}" -eq 0 ]; then
    echo "ERROR: PKGBUILD files not found in $ROOT" >&2
    exit 1
fi

for f in "${PKGBUILDS[@]}"; do

    # ------------------------------------------------------------------
    # 1) Комментарии к _processor_opt: документируем zen5
    # ------------------------------------------------------------------
    if ! grep -q 'znver5' "$f"; then
        sed -i 's|# - "zen4" (Use znver4 compiler optimizations)|# - "zen4" (Use znver4 compiler optimizations)\n# - "zen5" (Use znver5 compiler optimizations, AMD Zen 5 / Ryzen 9000)|' "$f"
    fi

    # ------------------------------------------------------------------
    # 2) case "$MARCH": добавляем ветки ZEN5 и GENERIC_V5
    # ------------------------------------------------------------------
    if ! grep -q 'MZEN5' "$f"; then
        python3 - "$f" <<'PYEOF'
import sys, re

path = sys.argv[1]
src = open(path).read()

old = '''            ZEN4) scripts/config -d GENERIC_CPU -e MZEN4 -d X86_NATIVE_CPU;;'''
new = '''            ZEN4) scripts/config -d GENERIC_CPU -e MZEN4 -d MZEN5 -d X86_NATIVE_CPU;;
            ZEN5) scripts/config -d GENERIC_CPU -d MZEN4 -e MZEN5 -d X86_NATIVE_CPU;;
            GENERIC_V5) scripts/config -e GENERIC_CPU -d MZEN4 -d MZEN5 -d X86_NATIVE_CPU --set-val X86_64_VERSION 5;;'''

assert old in src, f"anchor not found in {path}"
src = src.replace(old, new)

# во всех остальных местах -d MZEN4 дополняем -d MZEN5
src = src.replace('scripts/config -e GENERIC_CPU -d MZEN4 -d X86_NATIVE_CPU',
                  'scripts/config -e GENERIC_CPU -d MZEN4 -d MZEN5 -d X86_NATIVE_CPU')
src = src.replace('case "$MARCH" in\n            GENERIC_V[1-4])',
                  'case "$MARCH" in\n            GENERIC_V[1-5])')

open(path, 'w').write(src)
print(f"[zen5] patched MARCH case in {path}")
PYEOF
    fi

    # ------------------------------------------------------------------
    # 3) Не даём CI убивать оптимизацию (-Os вместо -O3/znver5)
    #    и не даём CI выключать CONFIG_CACHY
    # ------------------------------------------------------------------
    if grep -q 'CONFIG_CC_OPTIMIZE_FOR_SIZE\|CC_OPTIMIZE_FOR_SIZE' "$f" && grep -q '_is_ci_build' "$f"; then
        python3 - "$f" <<'PYEOF'
import sys

path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)
out = []
for l in lines:
    s = l.strip()
    if s.startswith('scripts/config') or s.startswith('-d CC_OPTIMIZE_FOR_PERFORMANCE_O3') \
       or s.startswith('-e CC_OPTIMIZE_FOR_SIZE') or s.startswith('-d DEBUG_KERNEL') \
       or s.startswith('-e DEBUG_INFO_REDUCED'):
        pass
    out.append(l)
src = ''.join(out)

# заменяем CI-блок понижения оптимизации на сохранение -O3 + CACHY
old_block = '''    ### CI-only stuff
    if _is_ci_build; then
        echo "Detected build inside CI"

'''
marker = '-d CC_OPTIMIZE_FOR_PERFORMANCE_O3'
if marker in src:
    i = src.index(marker)
    # найти конец блока (строка с DEBUG_INFO_REDUCED и перевод строки)
    jend = src.index('DEBUG_INFO_REDUCED', i)
    jend = src.index('\n', jend) + 1
    new_block = '''    ### CI-only stuff
    # NOTE(Zen5 build): upstream switches the kernel to -Os inside CI to keep
    # RAM/disk usage low on GitHub runners. We DO NOT want that, because our
    # whole goal is a znver5/-O3 optimized kernel built on a neutral server
    # CPU. Keep -O3 and Cachy tuning even in CI.
    if _is_ci_build; then
        echo "Detected build inside CI - keeping -O3/CACHY optimizations"
        scripts/config -e CC_OPTIMIZE_FOR_PERFORMANCE_O3 -d CC_OPTIMIZE_FOR_SIZE -e CACHY
'''
    src = src[:src.index('    ### CI-only stuff')] + new_block + src[jend:]
    open(path, 'w').write(src)
    print(f"[zen5] kept -O3/CACHY in CI for {path}")
PYEOF
    fi

done

echo "Done. zen5 support added to ${#PKGBUILDS[@]} PKGBUILD file(s)."
