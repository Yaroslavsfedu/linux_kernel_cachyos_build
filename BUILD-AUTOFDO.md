# AutoFDO: профильная оптимизация ядра под вашу машину (Zen 5)

Двухфазная схема: CI собирает **инструментированное** ядро → вы снимаете профиль
на реальной нагрузке (игры/сборка) на своём 9600X → CI собирает **финальное**
ядро, где clang оптимизирует hot paths по вашему профилю. Типичный прирост:
+3–8% на типичных нагрузках, лучший frame time за счёт выравнивания/раскладки кода.

Требования: Zen 4/5 (BRS) — ваш 9600X подходит; ThinLTO — уже включён.

## Фаза 1 — инструментированное ядро

1. **Actions → Build CachyOS kernel (Zen 5) → Run workflow**:
   `autofdo = instrumented` (остальное по умолчанию).
2. Дождитесь артефактов:
   - `linux-cachyos-zen5-thin-afdo-instrumented` — ядро с инструментированием
   - `vmlinux-instrumented` — vmlinux (нужен для конвертации профиля)
3. Установите ядро: `sudo pacman -U linux-cachyos-*.pkg.tar.zst` и загрузитесь в него.

## Фаза 2 — снятие профиля на своей машине

1. Ослабить права perf (только на время профилирования):

```bash
sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"
```

2. Нужен perf со сборкой libpfm (стандартный из repo не умеет pfm-events):

```bash
paru -S libpfm devtools
pkgctl repo clone --protocol=https linux-tools && cd linux-tools
rm PKGBUILD
wget https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/refs/heads/master/toolchain/linux-tools/PKGBUILD
makepkg -s
sudo pacman -U perf-*.tar.zst
```

3. Записать профиль **под реальной нагрузкой** (играйте 20–40 минут, или
   соберите ядро/распакуйте — профилировать надо то, чем пользуетесь):

```bash
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b \
    -c 500009 -o kernel.data -- sleep 1800
# 1800 секунд — снимайте прямо во время игры; скомпилированный процесс
# завершится сам, профилирование продолжится до конца sleep
```

4. Конвертировать в AutoFDO-профиль (распакуйте vmlinux из артефакта):

```bash
# create_llvm_prof — скачать бинарник из release v0.30.1:
# https://github.com/google/autofdo/releases
chmod +x create_llvm_prof
./create_llvm_prof --binary=./vmlinux --profile=kernel.data \
    --format=extbinary --out=kernel.afdo
```

## Фаза 3 — финальная сборка

1. Положить профиль в форк PKGBUILD'ов:

```bash
cp kernel.afdo /путь/к/linux-cachyos/linux-cachyos/
git add kernel.afdo && git commit -m "add AutoFDO profile" && git push
```

2. **Actions → Run workflow**: `autofdo = profile`. Соберётся ядро с
   `-fprofile-sample-use=kernel.afdo` поверх ThinLTO — именно ваши hot paths
   получат лучшую раскладку.

3. Установить и пользоваться. Хотите ещё +1–2% — потом можно добавить
   Propeller (второй проход: профиль уже AutoFDO-ядра), схема описана
   в комментариях PKGBUILD.

## Замечания

- Инструментированное ядро медленнее (~5–15%) — это нормально, оно только
  для снятия профиля.
- Профиль обновляйте при существенных изменениях ядра (новая версия 7.4 → 7.5)
  — иначе эффект вырождается. Из-за этого kbuild-патч `-salvage-stale-profile`
  в апстриме обсуждается; пока — просто переснимайте.
- Профиль `kernel.afdo` в форке — бинарный, ~несколько МБ; держать в git ок.
- Несколько профилей (игры + сборка) можно смержить `llvm-profgen` перед заливкой.
