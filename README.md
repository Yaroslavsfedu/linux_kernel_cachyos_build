# linux_kernel_cachyos_build

Сборщик ядра [CachyOS](https://github.com/CachyOS/linux-cachyos) под AMD Ryzen 5 9600X
(Zen 5 / znver5) на GitHub Actions.

Сборка качает PKGBUILD'ы и исходники ядра из форка
[Yaroslavsfedu/linux-cachyos](https://github.com/Yaroslavsfedu/linux-cachyos)
и нацелена на `-march=znver5` независимо от CPU раннера.

Подробности: [BUILD-ZEN5.md](BUILD-ZEN5.md) и [workflow](.github/workflows/build-zen5.yml).
