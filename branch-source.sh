#!/usr/bin/env bash
# ============================================================================
# branch-source.sh — подменяет в PKGBUILD релизный tarball исходников ядра
# на автоматический git-archive снапшот tip'а ветки форка Yaroslavsfedu/linux:
# ТЕКУЩИЕ файлы ветки и ничего больше — без истории, без .git, без релизов
# (это тот же контент, что отдаёт GitHub кнопкой "Download source archive").
#
# Аргументы:
#   $1 — каталог с PKGBUILD (например, pkgs/linux-cachyos)
#   $2 — ветка (по умолчанию из env LINUX_BRANCH, иначе 7.3/cachy)
#   env FORK_OWNER / FORK_KERNEL_REPO — владелец/репо форка (Yaroslavsfedu/linux)
#
# Действия над каталогом:
#   1. читает _srcname из PKGBUILD (имя каталога исходников, напр. cachyos-7.3.1-1);
#   2. качает снапшот: codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>;
#   3. переименовывает корень снапшота в $_srcname и упаковывает в
#      ${_srcname}.tar.gz рядом с PKGBUILD (PKGBUILD распаковывает тарбалл
#      и делает cd "$_srcname" — имя корня должно совпасть);
#   4. заменяет строку source() с парой релизных URL "{, .asc}" на локальный
#      файл ${_srcname}.tar.gz — подпись/b2sum релиза на подвижный снапшот
#      не рассчитаны (makepkg в CI работает с --skipchecksums).
# Идемпотентен: если source() уже локальный — успешный no-op.
# ============================================================================
set -euo pipefail

DIR="${1:?usage: branch-source.sh <dir-with-PKGBUILD> [branch]}"
BRANCH="${2:-${LINUX_BRANCH:-7.3/cachy}}"
OWNER="${FORK_OWNER:-Yaroslavsfedu}"
KERNEL_REPO="${FORK_KERNEL_REPO:-linux}"

cd "$DIR"

echo "[branch-source] dir=$(pwd) branch=$BRANCH repo=${OWNER}/${KERNEL_REPO}"

if ! grep -qF 'releases/download' PKGBUILD; then
    echo "[branch-source] source() уже не ссылается на релизный tarball — нечего делать"
    exit 0
fi

# ВАЖНО: source ./PKGBUILD выполняется в ЧИСТОМ bash (bash -c) — наш скрипт
# работает под set -euo pipefail, а PKGBUILD рассчитан на окружение makepkg:
# его дефолты разворачивают необязательные переменные среды
# (: "${_localmodcfg_path:="$XDG_DATA_HOME/..."}") и под set -u в CI это
# падение "unbound variable". В новом процессе опции -e/-u не наследуются,
# и source проходит так же, как у makepkg.
_srcname="$(bash -c 'source ./PKGBUILD >/dev/null 2>&1 && printf %s "${_srcname:-}"' || true)"
if [ -z "$_srcname" ]; then
    echo "[branch-source] ERROR: не удалось прочитать _srcname из PKGBUILD; проверь PKGBUILD построчно ниже" >&2
    sed -n '1,40p' PKGBUILD >&2
    exit 1
fi
echo "[branch-source] _srcname=${_srcname}"

snapshot="https://codeload.github.com/${OWNER}/${KERNEL_REPO}/tar.gz/refs/heads/${BRANCH}"
echo "[branch-source] Качаю снапшот ветки ${BRANCH} из ${OWNER}/${KERNEL_REPO}: ${snapshot}"
curl -fL --retry 3 --max-time 900 -o .branch-snapshot.tar.gz "$snapshot"

stage="$(mktemp -d)"
trap 'rm -rf "$stage" .branch-snapshot.tar.gz' EXIT

tar -xzf .branch-snapshot.tar.gz -C "$stage"
top="$(ls "$stage")"
test -n "$top" || { echo "[branch-source] ERROR: пустой снапшот?" >&2; exit 1; }
mv "$stage/$top" "$stage/$_srcname"

# SHA-1 tip'а ветки — для трассируемости в лог/артефакт (API, без jq).
sha="$(curl -fsSL --max-time 60 \
        "https://api.github.com/repos/${OWNER}/${KERNEL_REPO}/commits/${BRANCH}" \
        | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -n1 \
        | grep -o '[0-9a-f]\{40\}' || true)"
printf 'branch=%s\nsrcname=%s\ncommit=%s\ndate=%s\n' \
    "$BRANCH" "$_srcname" "${sha:-unknown}" "$(date -u +%FT%TZ)" \
    | tee branch-source.log

tar -czf "${_srcname}.tar.gz" -C "$stage" "$_srcname"

# Релизная пара URL "{,.asc}" находится на одной строке source() — заменяем её
# целиком на локальный файл (расширенное имя, чтобы и в комментариях не путать).
repl="    \"${_srcname}.tar.gz\""
sed -i "/releases\/download/s|.*|${repl}|" PKGBUILD

grep -nF "${_srcname}.tar.gz" PKGBUILD
grep -qF "${_srcname}.tar.gz" PKGBUILD || {
    echo "[branch-source] ERROR: замена source() не удалась" >&2
    exit 1
}
echo "[branch-source] OK: ядро теперь собирается из tip ветки ${BRANCH} (${OWNER}/${KERNEL_REPO})"
