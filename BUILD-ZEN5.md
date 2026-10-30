# Сборка ядра CachyOS под AMD Ryzen 5 9600X (Zen 5) через GitHub Actions

## Суть

Ryzen 5 9600X — это микроархитектура **Zen 5**, для GCC она называется **znver5**
(GCC ≥ 14.1 / Clang ≥ 18). Апстрим `CachyOS/linux-cachyos` из «ручных» оптимизаций
под CPU знает только `zen4`, а в CI ещё и принудительно переключает ядро на `-Os`.
Поэтому в этом репозитории лежат:

| Файл | Назначение |
|---|---|
| `.github/workflows/build-zen5.yml` | Workflow сборки на сервере GitHub Actions с параметрами под Zen 5 |
| `zen5-patches.sh` | Патчит PKGBUILD'ы: добавляет `_processor_opt=zen5` (`CONFIG_MZEN5`) и запрещает CI понижать оптимизацию до `-Os` |
| `linux-cachyos/`, `linux-cachyos-bore/`, `linux-cachyos-eevdf/` | PKGBUILD + config (принесены из CachyOS/linux-cachyos, уже пропатчены под zen5) |

## Почему сборка на чужом серверном CPU корректна

Важно понимать: **CPU раннера не участвует**. Кросс-оптимизация работает так:

* `_processor_opt=zen5` → в `.config` включается `CONFIG_MZEN5=y` →
  ядро компилируется с `-march=znver5 -mtune=znver5`, независимо от того,
  на чём крутится раннер (Xeon, EPYC Genoa и т.п.).
* `_processor_opt=native` / пустое значение = `CONFIG_X86_NATIVE_CPU` —
  **это ловушка**: тогда код заточится под серверный CPU раннера и на 9600X
  будет работать хуже generic-ядра. В workflow `native` не используется.
* Тот же принцип у X86_64_VERSION: `GENERIC_V4/V5` дают baseline-набор
  инструкций уровня x86-64-v4/v5 (AVX-512), но без tuning'а znver5.

## Параметры, выставленные под 9600X (в workflow)

```
_processor_opt   = zen5        # znver5: march+mtune под Zen 5 (главный флаг)
_cachy_config    = yes         # Cachy sauce твики (niche interactivity и т.д.)
_cpusched        = cachyos     # планировщик по умолчанию CachyOS (EEVDF+BORE-наследие)
_use_llvm_lto    = thin        # Thin LTO через clang/lld (быстро и заметно быстрее)
_cc_harder       = yes         # KBUILD_CFLAGS=-O3
_HZ_ticks        = 1000        # 1000 Hz — отзывчивость desktop
_tickrate        = full        # full dynticks
_preempt         = full        # full preemptive
_hugepage        = always      # THP always
_build_zfs       = no
_build_nvidia_open = no        # поставьте yes, если нужна GPU-модуль-сборка
```

Дополнительно `zen5-patches.sh` перебивает CI-блок апстрима, который делал
`-Os` внутри GitHub Actions — иначе вся «оптимизация под 9600X» терялась бы.

## Запуск

1. Push этого репозитория в GitHub (папки `linux-cachyos*` должны быть в корне).
2. **Actions → Build CachyOS kernel (Zen 5 / Ryzen 5 9600X) → Run workflow**
   (вариант, `processor_opt=zen5`, LTO и HZ выбираются во формах запуска).
3. Дождаться артефакта `linux-cachyos-zen5-thin/*.pkg.tar.zst`.

Шаг *Verify* в workflow сам проверяет, что в собранном пакете есть
`CONFIG_MZEN5=y` — если его нет, сборка считается непригодной.

## Установка результата на свой 9600X (Arch/CachyOS)

```bash
sudo pacman -U linux-cachyos-cachyos-lto-*-x86_64.pkg.tar.zst
# затем: linux-cachyos, initrd в grub/bootctl; либо через cachyos-hello
```

Проверка после загрузки:

```bash
uname -r                       # должен содержать cachyos
zcat /proc/config.gz | grep -E 'CONFIG_MZEN5|CC_OPTIMIZE_FOR_PERFORMANCE_O3|LTO_CLANG_THIN'
grep -m1 flags /proc/cpuinfo | grep -o 'avx512[a-z0-9_]*' | head   # Zen5 AVX-512 используется ядром косвенно
```

## Локальная сборка (без GitHub)

```bash
./zen5-patches.sh .            # один раз
cd linux-cachyos
_processor_opt=zen5 _use_llvm_lto=thin _cc_harder=yes makepkg -si --skipchecksums
```

## Замечания

* Для тонкой настройки можно включить AutoFDO/Propeller (`_autofdo=yes`), но
  профиль обязан быть снят **на вашем 9600X**, а не на сервере — поэтому в CI
  они выключены.
* Если хотите максимально «агрессивное» десктопное ядро — выберите
  `cpusched=bore`; для стабильности/RT — `eevdf`.
* Пакеты подписываются gpg-ключом сборщика; для продакшена добавьте свой
  `--sign` ключ в makepkg.

## Режимы количества драйверов (drivers_mode)

В форме запуска (workflow_dispatch) появился выбор **drivers_mode**:

| режим | что делает | время сборки |
|---|---|---|
| `trim` (по умолчанию) | `slim-config.py` ДО компиляции выключает ~1750 опций: VM-драйверы (Xen/Hyper-V/VirtIO/VMware), серверные NIC (Mellanox/Chelsio/QLogic…), RAID/HBA/FC/iSCSI, eMMC/UFS/NVDIMM, кластерные ФС (OCFS2/GFS2/AFS…), CAN/NFC/IIO/SPI/MFD, SoC-GPU и legacy-FB, sound-SoC, старый Wi-Fi. Ядро/сеть/ext4-xfs-btrfs-f2fs/USB-core/BT/Wi-Fi(iwlwifi,mt76,rtw8x,ath11k,ath12k)/amdgpu-i915-xe/snd-hda/KVM — остаются | заметно меньше 2 ч |
| `full` | полный дистрибутивный конфиг (~15500 модулей) | ~2 ч |
| `localmod` | штатный `_localmodcfg=yes`: PKGBUILD прогоняет `make localmodconfig` по базе modprobed.db вашего ПК | самая быстрая, ядро ровно под ваше железо |

### localmod: как подготовить базу с вашего ПК (Arch/CachyOS)
```bash
sudo pacman -S --aur modprobed-db        # или из AUR
modprobed-db store                        # записывает ~/.local/share/modprobed-db/modprobed.db
# затем файл modprobed.db нужно положить в CI: simplest — закоммитить в репозиторий
# linux-cachyos/modprobed.db и раскомментировать шаг copy в workflow (TODO ниже)
```
(в текущей сборке `trim` не требует никаких файлов — работает из коробки)
