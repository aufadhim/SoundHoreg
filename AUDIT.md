# SoundHoreg 0.2.0 — audit volume dan efisiensi

## Kesimpulan

Keluhan volume turun pada panggilan dan video belum berhasil direproduksi dengan sinyal uji. Tidak ada dasar untuk mengklaim bahwa penyebabnya sudah pasti stereo mixdown, speaker, atau kemampuan Apple Silicon.

Pada speaker MacBook Air, jalur lama dan jalur baru menerima sinyal uji pada level yang benar. Pengukuran digital setelah audio melewati pemrosesan juga menunjukkan gain yang benar. Ini tidak mengukur tekanan suara dari speaker atau mereproduksi panggilan/video pengguna.

Versi 0.2 menghindari jalur tambahan sepenuhnya pada 100%, tanpa EQ/balance/mono dan dengan output default. Pada kondisi ini audio tetap berada di jalur asli aplikasinya, sehingga SoundHoreg tidak dapat menurunkan levelnya atau menerapkan gain tambahan. Pada level lain/efek aktif, audio diproses seperti biasa.

## Pengukuran level lokal

Sumber: nada sinus 997 Hz, peak 0,02, stereo 48 kHz. Pengujian hanya membaca sinyal dari proses uji lokal, bukan merekam percakapan atau audio aplikasi pengguna. Jalur uji dibisukan saat pengukuran.

| Gain | Peak setelah pemrosesan versi 0.1 | Peak versi 0.2 | Target |
|---|---:|---:|---:|
| 50% | 0,0100000035 | 0,0100000035 | 0,01 |
| 100% | 0,01999979 | 0,020000001 | 0,02 |
| 200% | 0,039999574 | 0,03999961 | 0,04 |

Peak tap mixdown maupun device-stream sekitar 0,02 pada kedua versi. Dugaan atenuasi mixdown tidak terkonfirmasi pada speaker yang diuji. Device-stream tetap dipilih untuk menghindari normalisasi mixdown pada perangkat dengan susunan kanal berbeda. Perilaku tersebut didokumentasikan oleh pengembang binding Core Audio: https://docs.rs/coreaudio/latest/coreaudio/tap/struct.ProcessTap.html

200% adalah gain amplitudo 2× (+6,02 dB), bukan jaminan persepsi keras 2×. Materi yang sudah mendekati batas digital tidak dapat ditambah tanpa mencapai pembatas sampel; pengaturan gain tidak menambah kemampuan fisik speaker. Ini tidak dianggap sebagai diagnosis pasti keluhan pengguna.

## Masalah yang ditemukan dan diperbaiki

- Kanal mono: versi lama menebak dua buffer mono terakhir sebagai kiri/kanan. Pada aggregate dengan input fisik mono dan tap mono, ini dapat memilih input fisik sebagai kanal kiri. Versi baru menggunakan jumlah kanal yang dilaporkan tap, bukan menebaknya.
- Jalur netral: versi lama menjalankan tap, aggregate, callback dan filter bahkan pada gain 100% tanpa efek. Versi baru mengembalikan jalur asli pada konfigurasi netral.
- Jalur mute: memakai tap mute tanpa callback pemrosesan yang terus berjalan.
- Slider: langkah tepat 1% dan label dibulatkan, bukan menampilkan 100% untuk nilai pecahan yang berbeda.
- Perangkat berubah: listener mengikuti output dan sample rate, dan gagal koneksi dapat dicoba kembali setelah konfigurasi berubah.

## Perubahan efisiensi

- Pemindaian seluruh proses/perangkat hampir setiap 1,92 detik diganti listener Core Audio dan notifikasi workspace, dengan debounce 150 ms.
- Penyimpanan pengaturan slider di-debounce 350 ms.
- Perhitungan koefisien EQ dipindahkan dari callback ke saat pengaturan berubah.
- Jalur gain stereo tanpa efek memakai SIMD NEON Apple Silicon; EQ nol tidak menghitung filter per sampel.
- Meter tidak menghitung peak atau membuat timer ketika jendela tertutup, tertutup jendela lain, atau diminimalkan. Saat terlihat, meter diperbarui paling banyak 5 kali/detik, hanya bila nilainya berubah. Pembaruan meter tidak lagi menggambar ulang seluruh mixer.
- Sleep timer memakai timer satu kali pada deadline, bukan diperiksa setiap 120 ms.
- Tidak menambah polling, GPU work, ataupun power assertion yang mencegah Mac tidur.

Benchmark lokal 51,2 juta frame stereo, clang -O3, gain 22%:

| Jalur | Lama | Baru |
|---|---:|---:|
| Gain tanpa EQ | 0,338 detik; 6,61 ns/frame | 0,027 detik; 0,53 ns/frame |
| EQ aktif | 0,326 detik; 6,37 ns/frame | 0,336 detik; 6,56 ns/frame |

Jalur tanpa EQ sekitar 12× lebih cepat pada benchmark kernel. Perbedaan EQ kecil dan berada dalam variasi pengukuran; tidak diklaim lebih cepat. Angka ini bukan percepatan seluruh aplikasi dan bukan ukuran daya tahan baterai. Penghematan saat idle terutama berasal dari menghindari pekerjaan sama sekali.

## Verifikasi

- Build release Apple Silicon dan tanda tangan lokal.
- Tes DSP dengan AddressSanitizer dan UndefinedBehaviorSanitizer: unity, gain, mute, balance, mono, stereo planar/interleaved, input fisik+tap mono, pembatas sampel, non-finite input, meter mati, serta kesetaraan jalur SIMD dan scalar.
- Native UI: nama SoundHoreg, pengaturan WhatsApp lama tetap tersimpan; 100% menunjukkan “Level asli · hemat daya”.
- Audit runtime level setelah routing: tabel di atas.
- Pengukuran CPU singkat disimpan terpisah; hanya sampel proses, bukan pengukuran drain baterai atau uji panggilan jangka panjang.

Panggilan nyata, Bluetooth, perangkat multichannel, dan dampak kebijakan volume/ducking dari aplikasi lain masih memerlukan pengujian pada sesi yang menunjukkan masalah. Tidak ada kompensasi gain 2× tersembunyi untuk menutupi masalah yang belum terbukti.
