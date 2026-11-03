#!/usr/bin/env bash
# ============================================================================
# zen5-patches.sh — добавляет поддержку AMD Zen 5 (znver5) в PKGBUILD'ы
# linux-cachyos (апстрим знает только zen4/GENERIC_V1..V4/NATIVE, а в CI
# ещё и переключает сборку на -Os, теряя оптимизацию).
#
# Идемпотентно, только text-replace:
#   1. case "$MARCH": ветки ZEN5 -> CONFIG_MZEN5 и GENERIC_V5 -> x86-64-v5
#   2. все "-d MZEN4" дополняются "-d MZEN5" (конфиги не конфликтуют)
#   3. CI-блок апстрима (-Os вместо -O3) заменяется на сохранение -O3+CACHY
#
# Запуск: ./zen5-patches.sh [каталог]   (по умолчанию ".")
# В CI вызывается как: ./zen5-patches.sh pkgs
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

    # документируем zen5 в комментариях к _processor_opt
    if ! grep -q 'znver5' "$f"; then
        sed -i 's|# - "zen4" (Use znver4 compiler optimizations)|# - "zen4" (Use znver4 compiler optimizations)\n# - "zen5" (Use znver5 compiler optimizations, AMD Zen 5 / Ryzen 9000)|' "$f"
    fi

    # case "$MARCH": ветки ZEN5 и GENERIC_V5
    if ! grep -q 'MZEN5' "$f"; then
        python3 - "$f" <<'PYEOF'
import sys

path = sys.argv[1]
src = open(path).read()

old = '''            ZEN4) scripts/config -d GENERIC_CPU -e MZEN4 -d X86_NATIVE_CPU;;'''
new = '''            ZEN4) scripts/config -d GENERIC_CPU -e MZEN4 -d MZEN5 -d X86_NATIVE_CPU;;
            ZEN5) scripts/config -d GENERIC_CPU -d MZEN4 -e MZEN5 -d X86_NATIVE_CPU;;
            GENERIC_V5) scripts/config -e GENERIC_CPU -d MZEN4 -d MZEN5 -d X86_NATIVE_CPU --set-val X86_64_VERSION 5;;'''

if old not in src:
    print(f"[zen5] WARNING: anchor not found in {path} — пропущен (проверьте PKGBUILD)")
    sys.exit(0)

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

    # не даём CI понижать оптимизацию до -Os и выключать CONFIG_CACHY
    if grep -q 'CC_OPTIMIZE_FOR_SIZE' "$f" && grep -q '_is_ci_build' "$f"; then
        python3 - "$f" <<'PYEOF'
import sys

path = sys.argv[1]
marker = '-d CC_OPTIMIZE_FOR_PERFORMANCE_O3'
src = open(path).read()

if marker not in src or '### CI-only stuff' not in src:
    sys.exit(0)

i = src.index(marker)
jend = src.index('DEBUG_INFO_REDUCED', i)
jend = src.index('\n', jend) + 1

new_block = '''    ### CI-only stuff
    # NOTE(Zen5 build): апстрим в CI переключает ядро на -Os ради экономии
    # RAM/диска на раннере. Нам это не нужно: весь смысл — znver5/-O3 ядро,
    # собранное на нейтральном серверном CPU. Сохраняем -O3 и CACHY в CI.
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

echo "Done. zen5 support ensured in ${#PKGBUILDS[@]} PKGBUILD file(s)."
