# foston-leitor

Turns an old **Foston FS-M787S** tablet (Android 4.0.4) into a dedicated
e-reader. It boots straight into [KOReader](https://koreader.rocks), with
nothing else running in the background.

Everything runs from a Linux PC over `adb`: no root app, no custom ROM,
and the kernel and bootloader stay untouched. The original drivers keep
working: Wi-Fi, touch, battery and rotation.

> Português abaixo / Portuguese below: [ir para a versão em português](#português).

## Result

| | Before | After |
|---|---|---|
| Free RAM + cache | 141 MB | 280 MB |
| Running processes | 90 | 74 |
| At power-on | Android launcher | KOReader opens by itself |
| Home button | Launcher | "Leitor" screen ("Ler" / "Configurações") |

Measurements are in [`logs/`](logs/).

## How it works

```
Android 4.0.4 stock (kernel, drivers, SystemUI, Settings)
 ├─ 11 apps removed, 28 system apps disabled incl. launcher (pm disable, reversible)
 ├─ KOReader v2023.06 (last release that supports Android 4.0–4.2)
 └─ Leitor (br.com.luan.leitor), small app of our own:
     ├─ the only HOME screen (Launcher2 disabled)
     ├─ BOOT_COMPLETED → opens KOReader once per boot
     └─ two buttons: "Ler" (KOReader) and "Configurações" (Android settings)
```

Books get onto the tablet over USB (USB mass storage, `Livros/` folder) or
over Wi-Fi from inside KOReader (OPDS catalog, Calibre, SSH/FTP). Wi-Fi
stays off until you turn it on.

## Requirements

- Linux PC with `bash`, `curl`, `unzip`, `zip`, `python3`. No sudo needed,
  except for the udev rule below.
- Tablet with **USB debugging** on (Settings → About → tap "Build number"
  7 times → Developer options → USB debugging).
- On this model the `adb shell` already runs as root (`ro.secure=0`). The
  scripts check this and stop otherwise.

udev rule so your user can talk to the tablet over USB (run once, as
root):

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Usage, in order

```bash
scripts/setup-toolchain.sh                                   # adb, JDK 21, Android SDK in ~/.local/opt
scripts/backup.sh                                            # full NAND copy to ~/foston-backup/2026-10-16
scripts/health.sh 01-antes                                   # memory snapshot
scripts/apply-packages.sh uninstall packages/remove.txt
scripts/apply-packages.sh disable packages/disable-1-google.txt
scripts/apply-packages.sh disable packages/disable-2-apps.txt
scripts/apply-packages.sh disable packages/disable-3-visual.txt
scripts/install-koreader.sh                                  # KOReader + Livros/ + sample books
app/build.sh                                                 # builds app/build/leitor.apk
~/.local/opt/platform-tools/adb install -r app/build/leitor.apk
scripts/apply-packages.sh disable packages/disable-4-launcher.txt   # always last
```

Reboot after each `disable` batch and check that everything still works.
Only disable the launcher (`disable-4`) after confirming that Leitor opens
and that the "Ler" and "Configurações" buttons work.

### Backup

`backup.sh` copies the 10 NAND partitions (`nanda`…`nandj`, about 3.7 GB)
in 64 MiB chunks and checks each image's md5 against the device. While it
copies, it pauses the Android interface (`stop`) and remounts `/data`
read-only. If anything fails, a `trap` always brings the device back. On a
rerun it skips the partitions that are already verified.

## Undoing

| Problem | Command |
|---|---|
| You need a disabled app back | `scripts/apply-packages.sh enable packages/<list>.txt` (or `adb shell pm enable <package>`) |
| You want the original home screen back | `scripts/apply-packages.sh enable packages/disable-4-launcher.txt` |
| Remove Leitor | **first** enable the launcher (line above), then `adb uninstall br.com.luan.leitor` |
| Android won't boot but adb responds | restore `nandd`/`nande` from the images with `dd` |
| adb doesn't respond | A13 FEL mode + PhoenixSuite/LiveSuite with a factory image |

Nothing here writes to `nanda`–`nandc` (boot, kernel) or to `/system`.

## Lessons from Android 4.0 over adb

If you adapt this to another old tablet, these cost hours:

- **The 4.0 `adbd` does not return the command's exit code.** Every
  `adb shell` "succeeds". Check the output text instead (`Success`,
  `new state: disabled`, the `mount` state).
- **`adb exec-out` does not exist.** To copy a partition: `dd` to a file
  on the device, then `adb pull`, in chunks.
- **Never stage the copy inside the partition you are copying.** The
  first backup wrote its chunks to `/data/local/tmp` (inside `nande`), so
  the md5 never matched. It now uses `/cache`.
- **Output comes back with CRLF.** Strip it with `tr -d '\r'`.
- **`adb` inside `while read` eats the loop's stdin.** Use `</dev/null`,
  or only the first item gets processed (that happened here).
- **`adb shell … | grep -q` under `set -o pipefail` fails at random**
  (SIGPIPE). Capture the output into a variable first.
- **toolbox has no `grep`/`head`/`sed`, and `rm` has no `-f`.** Do the
  text processing on the PC.
- **The internal storage becomes a USB drive on the PC** while the cable
  is plugged in, and disappears from the device. Get it back with
  `vdc volume unshare /mnt/sdcard ums` + `vdc volume mount /mnt/sdcard`.
- **KOReader dropped Android 4.0–4.2 after v2023.06.** Current releases
  ask for 4.3+.
- **javac 21 + d8 crash on anonymous classes** (`NullPointerException` on
  `<parameter1>`). Compiling with `-parameters` fixes it.

## Structure

```
scripts/     setup, backup, health, packages, KOReader
packages/    package lists (one per line, # for comments)
app/         Leitor: AndroidManifest, res/, src/, build.sh (aapt2 + javac + d8 + apksigner, no Gradle)
logs/        memory/process snapshots at each step
docs/        original design and implementation plan (historical record)
```

The documents in `docs/superpowers/` record the design and plan as they
were written. Some details changed during implementation. The most
important: opening KOReader once per boot was first done by comparing
`elapsedRealtime`, which was flawed, and it became a `BOOT_COMPLETED`
receiver. The commit history tells the rest.

## License

[MIT](LICENSE). KOReader is a separate project, under AGPL-3.0, and is
downloaded from its official release. It is not redistributed here.

---

## Português

Transforma um tablet antigo **Foston FS-M787S** (Android 4.0.4) num leitor
de livros digitais dedicado. Ele liga direto no
[KOReader](https://koreader.rocks), sem nada rodando em segundo plano.

Tudo é feito a partir de um PC com Linux via `adb`: sem app de root, sem
ROM customizada, e o kernel e o bootloader ficam intactos. Os drivers
originais continuam funcionando: Wi-Fi, touch, bateria e rotação.

### Resultado

| | Antes | Depois |
|---|---|---|
| RAM livre + cache | 141 MB | 280 MB |
| Processos rodando | 90 | 74 |
| Ao ligar | launcher do Android | KOReader abre sozinho |
| Botão Home | launcher | tela "Leitor" ("Ler" / "Configurações") |

As medições estão em [`logs/`](logs/).

### Como funciona

- 11 apps removidos e 28 apps de sistema desativados com `pm disable` (incluindo o launcher).
  Dá para reverter.
- KOReader v2023.06, a última versão que roda em Android 4.0–4.2.
- "Leitor" (`br.com.luan.leitor`), um app próprio pequeno. Ele é a única
  tela inicial, abre o KOReader uma vez a cada boot (`BOOT_COMPLETED`) e
  tem os botões "Ler" e "Configurações".

Os livros entram pelo cabo USB (armazenamento USB, pasta `Livros/`) ou pelo
Wi-Fi dentro do KOReader (catálogo OPDS, Calibre, SSH/FTP). O Wi-Fi fica
desligado até você ligar.

### Uso

Os requisitos, a regra udev e a ordem dos comandos estão nas seções
[Requirements](#requirements) e [Usage, in order](#usage-in-order). Os
comandos são os mesmos.

Reinicie o tablet depois de cada lote de `disable` e confira se tudo
funciona. Desative o launcher (`disable-4`) só no final, depois de
confirmar que o Leitor abre e que os botões "Ler" e "Configurações"
funcionam.

### Desfazer

- App desativado que fez falta: `scripts/apply-packages.sh enable packages/<lista>.txt`.
- Voltar a tela inicial original: `scripts/apply-packages.sh enable packages/disable-4-launcher.txt`.
- Remover o Leitor: **antes** reative o launcher, depois rode `adb uninstall br.com.luan.leitor`.
- Android não sobe, mas o adb responde: restaure `nandd`/`nande` a partir
  das imagens do backup com `dd`.
- O adb não responde: modo FEL do A13 + PhoenixSuite/LiveSuite com uma
  imagem de fábrica.

### Lições

As armadilhas do Android 4.0 via adb estão listadas em
[Lessons from Android 4.0 over adb](#lessons-from-android-40-over-adb).
As principais: o adbd não devolve o código de saída, a saída vem com
CRLF, o `adb` dentro de `while read` consome o stdin do loop, e a cópia
nunca pode gravar seus pedaços temporários dentro da partição que está
sendo copiada.

### Licença

[MIT](LICENSE). O KOReader é um projeto separado, sob AGPL-3.0, baixado
do release oficial dele. Ele não é redistribuído aqui.
