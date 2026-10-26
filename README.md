# SoundHoreg · 0.2.0 preview

Aplikasi native macOS untuk mengatur audio per aplikasi, dibuat untuk Mac Apple Silicon. Minimal macOS 14.4. Tidak ada masa trial, desis tambahan, iklan, atau koneksi jaringan. Audio diproses di memori, tidak disimpan sebagai rekaman.

## Build dari source

Memerlukan Mac Apple Silicon, macOS 14.4+, dan Apple Command Line Tools.

```sh
git clone https://github.com/aufadhim/SoundHoreg.git
cd SoundHoreg
./build.sh
open build/SoundHoreg.app
```

File aplikasi hasil build tidak disimpan dalam repository.

## Mulai

1. Buka **SoundHoreg.app** hasil build di folder `build/`.
2. Putar video atau buka aplikasi panggilan. Daftar akan diperbarui otomatis.
3. Aktifkan **Atur** pada aplikasi yang ingin dikendalikan. Izinkan System Audio Recording jika macOS memintanya. Bila izin ditolak, buka System Settings → Privacy & Security → Screen & System Audio Recording, aktifkan SoundHoreg, lalu buka ulang aplikasinya.
4. Atur volume panggilan dan video secara terpisah, atau pilih **Nonton + Telepon**. Preset cepat ini mengatur aplikasi panggilan yang terdeteksi menjadi 22% dan aplikasi video/browser yang terdeteksi menjadi 100%.
5. Klik ikon slider di kanan baris untuk membuka balance, bass/treble, mono, output, dan sleep timer.

**Bypass** mengembalikan jalur asli semua aplikasi. Shortcut saat SoundHoreg aktif: ⌘⇧B. Tutup jendela untuk tetap menjalankan SoundHoreg di menu bar. Pilih **Keluar SoundHoreg** untuk menghentikannya sepenuhnya.

## Fitur

- Volume 0–200%, mute, solo, dan meter per aplikasi. 100% tanpa efek/output khusus memakai jalur asli; 200% adalah +6 dB gain digital.
- Master volume untuk aplikasi yang tombol Atur-nya aktif.
- Balance kiri/kanan, mono, bass dan treble ±12 dB per aplikasi.
- Output berbeda untuk tiap aplikasi; mengikuti output Mac secara default.
- Menyimpan pengaturan per aplikasi dan beberapa preset buatan sendiri.
- Sleep timer untuk mute otomatis setelah 15, 30, atau 60 menit; timer berlaku selama aplikasi berjalan.
- Pengelompokan proses helper browser dan daftar proses latar opsional.
- Mode hemat daya: listener macOS menggantikan polling, SIMD NEON untuk gain stereo, dan meter berhenti saat jendela tidak terlihat.
- Ramping perubahan gain dan pembatas sampel ke rentang -1…1 untuk menghindari overflow digital. Boost/EQ besar masih dapat terdengar distorsi.
- Pemulihan jalur audio asli saat bypass, keluar, atau gagal menyiapkan channel.

Solo hanya mematikan aplikasi lain yang juga tombol Atur-nya aktif. Master tidak mengubah volume perangkat Mac. Preset tidak menyimpan master, solo, bypass, atau timer. Preset Nonton + Telepon diterapkan ke aplikasi yang sudah terdeteksi pada saat tombol ditekan; bukan detektor panggilan otomatis.

## Status pengujian dan batasan

Ini versi awal yang dapat dijalankan, belum produk setara atau lebih unggul secara keseluruhan daripada SoundSource.

- Build release berhasil pada macOS 26.6.2 / Apple Silicon.
- Antarmuka native diperiksa langsung; WhatsApp, Safari, Brave, Chrome terdeteksi.
- Jalur Core Audio Safari diaktifkan dan menerima ribuan callback tanpa error; ini memverifikasi jalur pemrosesan berjalan, bukan penilaian kualitas dengar.
- Tes DSP mencakup gain, mute, balance, mono, pemetaan buffer aggregate, input planar, clipping guard, dan nilai non-finite dengan AddressSanitizer + UndefinedBehaviorSanitizer.
- Panggilan WhatsApp, Telegram, FaceTime, perpindahan output, dan Bluetooth belum diuji menyeluruh. FaceTime dapat memutar audio lewat proses TelephonyUtilities/avconferenced; tampilkan Proses latar jika diperlukan. Proses sistem yang dipakai bersama tidak selalu dapat dipisahkan menurut jendela aplikasi.
- Semua tab dalam satu browser diatur bersama. Tidak ada pengaturan per tab, Audio Unit plug-in, EQ parametrik multiband, auto-ducking, atau penghilang noise mikrofon pada versi ini.
- Izin audio bergantung macOS. Konten terlindungi dan beberapa aplikasi mungkin tidak dapat ditangkap. Jika terdengar masalah, aktifkan Bypass atau nonaktifkan Atur.
- Dukungan format saat ini PCM Float32, output mono/stereo. Output multichannel hanya diisi dua kanal pertama.
- Ditandatangani secara lokal untuk Mac ini, belum dinotarisasi untuk distribusi publik.

Rincian audit volume dan benchmark ada di [AUDIT.md](AUDIT.md). Identitas internal aplikasi tetap dipertahankan agar pengaturan lama ikut terbawa saat nama berubah.

Diagnostik lokal bisa disimpan dari menu roda gigi; file `suara-diagnostics.txt` berada di folder sementara macOS. Isinya nama proses/perangkat dan status channel, tidak memuat rekaman suara.

## Build ulang

Jalankan `./build.sh` dari folder proyek. Memerlukan Command Line Tools Apple; tidak memerlukan paket pihak ketiga. Hasil di `build/SoundHoreg.app`. Source SwiftUI/Core Audio berada di `Sources/` dan tes DSP di `Tests/`.

Build khusus Apple Silicon. Mengganti binary dapat membuat macOS meminta izin audio ulang.
