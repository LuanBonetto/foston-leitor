# Foston FS-M787S como e-reader — design

Data: 2026-10-16
Status: aprovado em conversa, aguardando revisão do spec

## Objetivo

Transformar o tablet Foston FS-M787S num leitor dedicado de livros digitais
(EPUB, PDF, MOBI, FB2, DjVu, CBZ), com o mínimo de processos em segundo plano
para economizar RAM e bateria. Ao ligar, o tablet abre direto no leitor.

## Decisões tomadas

- Manter o Android de fábrica (kernel e drivers originais). Linux próprio foi
  descartado porque Wi-Fi, touch e controle de bateria dependem de drivers
  fechados sem garantia de suporte no Linux mainline.
- Leitor: KOReader **v2023.06** (APK `koreader-android-arm-v2023.06.apk`).
  É a última versão que suporta Android 4.0–4.2; as versões atuais exigem
  Android 4.3+ (koreader/koreader#10614).
- Livros entram por cabo USB e por Wi-Fi sob demanda. Wi-Fi fica desligado
  por padrão.

## Hardware levantado (via adb, somente leitura)

| Item | Valor |
|---|---|
| Modelo | FS-M787S (`ro.product.model`) |
| SoC | AllWinner A13 (`sun5i`, rev `a13b`), ARMv7 single-core, NEON |
| RAM | 360 MB (`MemTotal: 361936 kB`) |
| Android | 4.0.4, API 15 |
| ABI | `armeabi-v7a` |
| adb | shell já é root (`ro.secure=0`, `ro.debuggable=1`) |
| USB | `18d1:0003`, serial adb `20080411413fc082`, `sys.usb.config=mass_storage,adb` |

Partições NAND (`/proc/partitions`, tamanhos em blocos de 1 KiB):

| Bloco | Tamanho | Uso |
|---|---|---|
| nanda | 16 MiB | boot/bootloader (não tocar) |
| nandb | 16 MiB | env/misc (não tocar) |
| nandc | 32 MiB | boot (kernel) (não tocar) |
| nandd | 384 MiB | `/system` (ext4) |
| nande | 1 GiB | `/data` (ext4) |
| nandf | 16 MiB | misc |
| nandg | 32 MiB | recovery |
| nandh | 256 MiB | `/cache` (ext4) |
| nandi | 256 MiB | private/outros |
| nandj | ~1,7 GiB | armazenamento interno `/mnt/sdcard` (FAT) |

Os usos de nanda–nandc e nandf–nandi seguem o layout típico de firmware A13
e não foram confirmados; isso não muda o plano, porque o backup copia todas.

Armazenamento: `nandj` é montado em `/mnt/sdcard` pelo vold. Com o cabo USB
ligado ele é compartilhado com o PC como USB mass storage e fica desmontado no
tablet (aparece no PC como disco de ~1,7 GB). O slot microSD monta em
`/mnt/extsd`.

## Arquitetura

```
Android 4.0.4 de fábrica (kernel, drivers, SystemUI, Configurações)
  └─ Leitor (mini-launcher próprio, category.HOME)
       ├─ no boot: abre o KOReader
       ├─ botão "Ler": abre o KOReader
       └─ botão "Configurações": abre android.settings.SETTINGS
  └─ KOReader v2023.06 (pasta de livros /mnt/sdcard/Livros)
```

## Componentes

### 1. Backup completo (antes de qualquer mudança)

- Diretório no PC: `~/foston-backup/2026-10-16/`.
- Para cada `nanda`…`nandj`: `adb exec-out "dd if=/dev/block/nandX bs=1M"`
  para `nandX.img`. A partição `nandj` é copiada com o compartilhamento USB
  desligado, para não ler um volume montado pelo PC.
- Checksum: `md5sum` da partição no tablet (busybox se existir; senão
  `adb exec-out cat | md5sum` duas vezes) comparado com `md5sum` do `.img`.
- Salvar também: `pm list packages -f`, `getprop`, `/system/build.prop`,
  `/system/etc/vold.fstab`.
- Critério de aceite: 10 imagens com tamanho igual ao de `/proc/partitions`
  e checksums iguais.

### 2. Limpeza

Remover (instalados em `/data/app`, via `adb uninstall`):
`com.adobe.flashplayer`, `com.android.vending`, `com.dataviz.docstogo`,
`com.google.android.gms`, `com.google.android.voicesearch`,
`com.google.android.youtube`, `com.instagram.android`,
`com.opera.mini.native`, `com.skype.raider`, `com.spb.shell3d`,
`miyowa.android.microsoft.wlm`, `yuku.mp3recorder.full`.

Desativar (sistema, via `pm disable`, reversível com `pm enable`):
`com.google.android.gm`, `com.google.android.syncadapters.calendar`,
`com.google.android.syncadapters.contacts`, `com.google.android.feedback`,
`com.google.android.gsf.login`, `com.google.android.gsf`,
`com.google.android.partnersetup`, `com.google.android.googlequicksearchbox`,
`com.android.quicksearchbox`, `com.google.android.apps.uploader`,
`com.google.android.location`, `com.android.vending.updater`,
`com.android.facelock`, `com.android.wallpaper`,
`com.android.wallpaper.livepicker`, `com.android.email`,
`com.android.exchange`, `com.android.camera`, `com.android.gallery3d`,
`com.android.music`, `com.android.musicfx`, `com.android.music.tests`,
`com.android.calendar`, `com.android.calculator2`, `com.android.deskclock`,
`com.android.browser`, `com.android.launcher` (este só depois que o Leitor
estiver instalado e testado).

Manter: Configurações, `com.android.inputmethod.latin`, SystemUI,
`com.android.packageinstaller`, `com.softwinner.explore`, providers do
sistema (settings, media, downloads, applications, telephony, user
dictionary, drm), `com.android.phone`, `com.android.keychain`,
`com.android.certinstaller`, `com.android.defcontainer`,
`tw.com.domintech.gsensor`, `com.mcube.acc`, `com.svox.pico`,
`com.android.htmlviewer`, `com.android.provision`, `com.android.backupconfirm`,
`com.android.sharedstoragebackup`, `com.android.vpndialogs`,
`com.android.smspush`, `com.android.providers.calendar`,
`com.android.providers.contacts`.

Regra: desativar um pacote por vez em lotes pequenos e reiniciar ao fim de
cada lote. Se o sistema mostrar "processo parou" em loop, `pm enable` do
último lote.

Critério de aceite: o tablet reinicia, Wi-Fi conecta, touch e rotação
funcionam, e `MemFree + Cached` em `/proc/meminfo` sobe em relação à medida
anterior (registrar antes e depois).

### 3. KOReader

- Baixar `https://github.com/koreader/koreader/releases/download/v2023.06/koreader-android-arm-v2023.06.apk`
  e conferir o tamanho (32 648 511 bytes).
- `adb install` e abrir uma vez para criar os arquivos de configuração.
- Configurar: pasta inicial `/mnt/sdcard/Livros`; tela cheia; catálogo OPDS
  do Project Gutenberg; Wi-Fi desligado ao abrir.
- Criar `/mnt/sdcard/Livros/`.

Critério de aceite: abre um EPUB e um PDF de exemplo e passa páginas.

### 4. Leitor (mini-launcher)

- Repositório: `~/code/foston-leitor/`.
- Pacote `br.com.luan.leitor`, `minSdkVersion 15`, `targetSdkVersion 15`.
- Uma `Activity` com intent-filter `MAIN` + `HOME` + `DEFAULT`, layout com dois
  botões grandes: "Ler" e "Configurações".
- Abre o KOReader com
  `getPackageManager().getLaunchIntentForPackage("org.koreader.launcher")`;
  se não achar o pacote, mostra uma mensagem na tela e mantém o botão
  "Configurações".
- Abre o KOReader automaticamente só na primeira vez após o boot (flag em
  memória do processo), para o botão Voltar do KOReader cair na tela do
  Leitor em vez de entrar em loop.
- Build sem Android Studio: JDK e Android build-tools instalados em
  `~/.local` sem sudo; build via Gradle com `compileSdk` compatível e
  `minSdk 15`. APK assinado com keystore de debug local.

Critério de aceite: após reboot o KOReader abre sozinho; Voltar no KOReader
mostra o Leitor; "Configurações" abre as Configurações; Home sempre volta
ao Leitor.

## Ordem de execução

1. Backup e verificação (componente 1).
2. Remoção dos apps de `/data/app`; reboot; medir.
3. Desativação dos apps de sistema, exceto `com.android.launcher`; reboot;
   medir.
4. KOReader instalado e configurado.
5. Leitor compilado, instalado e testado com o Launcher2 ainda ativo
   (escolha manual de tela inicial).
6. Desativar `com.android.launcher`; reboot; teste final.

## Tratamento de erros e volta atrás

| Problema | Ação |
|---|---|
| App desativado fez falta | `pm enable <pacote>` |
| Leitor com defeito | `adb uninstall br.com.luan.leitor` e `pm enable com.android.launcher` |
| Loop de "processo parou" | `pm enable` do último lote desativado |
| Android não sobe, adb funciona | restaurar `nandd`/`nande` a partir das imagens |
| adb não responde | modo FEL do A13 + PhoenixSuite/LiveSuite com imagem de fábrica |

Nenhuma etapa grava em nanda, nandb, nandc (boot, kernel) nem em `/system`.

## Fora do escopo

Trocar kernel, fazer overclock ou undervolt, atualizar o Android, instalar
Google Play ou qualquer app além do KOReader e do Leitor.
