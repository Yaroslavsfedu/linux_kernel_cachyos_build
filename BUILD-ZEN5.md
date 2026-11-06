# Сборка ядра CachyOS с оптимизацией под Zen 5 (znver5) через GitHub Actions

## Суть

Zen 5 — микроархитектура AMD (Ryzen 9000), в GCC/Clang она называется **znver5**
(GCC ≥ 14.1 / Clang ≥ 18). Апстрим `CachyOS/linux-cachyos` знает только `zen4`,
а в CI ещё и принудительно переключает ядро на `-Os`. Поэтому:

| Файл | Назначение |
|---|---|
| `.github/workflows/build-zen5.yml` | Workflow сборки: клонирует форк и собирает ядро с параметрами под Zen 5 |
| `zen5-patches.sh` | Патчит PKGBUILD'ы после клонирования: добавляет `_processor_opt=zen5` (`CONFIG_MZEN5`), запрещает CI понижать оптимизацию до `-Os` |

## Автономная схема (кто что качает)

Отдельные копии PKGBUILD'ов в этом репо НЕ хранятся — нет дубляжа:

1. **Сборщик** — этот репозиторий (`linux_kernel_cachyos_build`).
2. **PKGBUILD + config** — форк [`Yaroslavsfedu/linux-cachyos`](https://github.com/Yaroslavsfedu/linux-cachyos)
   (ветка `master`). Правки ядра/конфига делаются там; workflow клонирует его
   на каждом запуске и накладывает zen5-патчи на лету.
3. **Tarball исходников ядра** — релиз того же форка
   (`https://github.com/Yaroslavsfedu/linux-cachyos/releases/tag/cachyos-7.3.1-1`).
   Это зеркало tarball'а `CachyOS/linux`: байты идентичны, поэтому PGP-подписи
   мейнтейнеров CachyOS и b2sums остаются валидны.
   Если релиза у форка ещё нет — workflow автоматически откатывается на релиз
   `CachyOS/linux` под версию, зашитую в PKGBUILD.

### Создать/обновить зеркало исходников (при выходе новой версии ядра)

В форке `Yaroslavsfedu/linux-cachyos`:

```bash
./mirror-release.sh cachyos-7.3.1-1     # номер версии = тег релиза CachyOS/linux
```

Нужен авторизованный `gh` (`gh auth login`). Скрипт скачает tar.gz + .asc,
проверит подпись и создаст релиз в форке. PKGBUILD'ы уже указывают на этот релиз.

## Почему сборка на чужом серверном CPU корректна

**CPU раннера не участвует.** Кросс-оптимизация:

* `_processor_opt=zen5` → в `.config` включается `CONFIG_MZEN5=y` →
  ядро компилируется с `-march=znver5 -mtune=znver5`, независимо от CPU раннера
  (Xeon, EPYC Genoa и т.п.).
* `_processor_opt=native` / пустое значение = `CONFIG_X86_NATIVE_CPU` — **ловушка**:
  код заточится под серверный CPU раннера и на целевой машине с Zen 5 будет работать хуже generic.
  В workflow `native` не используется.
* `GENERIC_V4/V5` дают baseline инструкций уровня x86-64-v4/v5 (AVX-512) без tuning'а znver5.

## Параметры, выставленные под Zen 5 (в workflow)

```
_processor_opt   = zen5        # znver5: march+mtune под Zen 5 (главный флаг)
_cachy_config    = yes         # Cachy sauce твики
_cpusched        = cachyos     # планировщик по умолчанию CachyOS (EEVDF)
_use_llvm_lto    = thin        # Thin LTO через clang/lld
_cc_harder       = yes         # KBUILD_CFLAGS=-O3
_HZ_ticks        = 1000        # отзывчивость desktop
_tickrate        = full        # full dynticks
_preempt         = full        # full preemptive
_hugepage        = always      # THP always
_build_zfs       = no
_build_nvidia_open = no
```

`zen5-patches.sh` дополнительно перебивает CI-блок апстрима, который понижал
оптимизацию до `-Os`, иначе вся «оптимизация под Zen 5» терялась бы.

## Запуск

1. Push этого репозитория и форка `linux-cachyos` (PKGBUILD'ы качаются из него).
2. **Actions → Build CachyOS kernel (Zen 5) → Run workflow**
   (вариант, LTO, HZ выбираются в форме запуска).
3. Дождаться артефакта `linux-cachyos-zen5-thin/*.pkg.tar.zst`.

## Конфиг ядра (свой спец-конфиг)

Конфиг берётся из форка как есть: PKGBUILD делает `cp ../config .config`,
затем поверх через `scripts/config` применяются только параметры запуска
(`_processor_opt`, `_cpusched`, `_HZ_ticks` и т.д.).

**Свой конфиг = правишь `config` в форке `Yaroslavsfedu/linux-cachyos`**
(папка выбранного варианта) и push. Workflow ничего не режет и не переписывает.

## Установка результата (Arch/CachyOS)

```bash
sudo pacman -U linux-cachyos-cachyos-*.pkg.tar.zst
# затем: linux-cachyos-headers для сборки модулей; initrd в grub/bootctl
```

Проверка после загрузки:

```bash
uname -r                       # должен содержать cachyos
zcat /proc/config.gz | grep -E 'CONFIG_MZEN5|CC_OPTIMIZE_FOR_PERFORMANCE_O3|LTO_CLANG_THIN'
```

## Локальная сборка (без GitHub)

```bash
git clone --depth 1 https://github.com/Yaroslavsfedu/linux-cachyos.git
./zen5-patches.sh linux-cachyos
cd linux-cachyos
_processor_opt=zen5 _use_llvm_lto=thin _cc_harder=yes makepkg -si --skipchecksums
```

## Замечания

* AutoFDO/Propeller можно включить (`_autofdo=yes`), но профиль должен сниматься
  на целевой машине, поэтому в CI они выключены.
* Пакеты подписываются gpg-ключом сборщика; для продакшена добавьте свой ключ.
