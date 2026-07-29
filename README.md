# agentop

TUI untuk memantau workflow multi-agent Claude Code secara live, dari terminal.

![agentop memantau satu run workflow: delapan agen, dua gagal, dua macet](docs/demo.gif)

Rekaman itu `agentop --demo`, satu run bawaan yang tidak menyentuh disk sama sekali — jadi tidak ada nama proyek atau isi transcript siapa pun di dalamnya. Jalankan sendiri tanpa memasang apa-apa lebih dulu.

## Masalah

Claude Code punya `/workflows` untuk memantau progres workflow multi-agent (banyak subagent jalan paralel, bisa puluhan menit), tapi slash command itu cuma tersedia di CLI/TUI resmi. Pengguna extension VSCode tidak punya cara melihat progres workflow yang sedang jalan sama sekali.

`agentop` tidak menyambung ke Claude Code lewat API atau protokol apa pun, dan tidak menghubungi siapa pun. Ia cuma membaca berkas yang memang sudah ditulis Claude Code ke disk selama workflow jalan, lalu menyajikannya sebagai TUI yang bisa dipakai dari terminal mana pun, terlepas dari editor yang dipakai untuk memicu workflow-nya.

Tidak ada kunci API, tidak ada akun, tidak ada layanan yang kami jalankan. Nanti akan ada `agentop serve` untuk konsumen yang tidak bisa menjangkau disk — misalnya ponsel lewat Tailscale — tapi bahkan itu cuma **mendengarkan** di alamat yang kamu tentukan, bawaannya loopback. Rinciannya di [ARCHITECTURE.md](ARCHITECTURE.md).

## Yang dibaca dari disk

Untuk tiap run workflow, Claude Code menulis direktori:

```
<akar-config>/projects/<project-slug>/<session-id>/subagents/workflows/wf_<runid>/
  journal.jsonl              satu baris per event (agent mulai / agent selesai)
  agent-<id>.jsonl           transcript penuh tiap subagent
  agent-<id>.meta.json       tipe agent, kedalaman spawn, model
```

`journal.jsonl` menentukan berapa agent yang sudah mulai dan berapa yang sudah melapor selesai; transcript tiap agent dibaca inkremental (hanya delta byte yang baru) karena berkasnya bisa tumbuh sampai beberapa megabyte selama workflow jalan.

**Kedua akar config dipindai**: `~/.claude` (config personal) dan `~/.claude-work` (config kerja/organisasi). agentop menampilkan run dari keduanya tanpa perlu dipilih.

## Cara pasang

Repo publik ini cuma berisi README, LICENSE, `install.sh`, dan Releases —
source-nya ada di repo private terpisah, jadi `go install` tidak berlaku di
sini. Pilih salah satu dari tiga jalur berikut (tersedia setelah rilis
pertama dipublikasikan):

Lewat Homebrew:

```
brew install pimlabs/tap/agentop
```

Lewat npm:

```
npm install -g @pimlabs/agentop
```

Lewat skrip pasang:

```
curl -fsSL https://raw.githubusercontent.com/pimlabs/agentop/main/install.sh | sh
```

## Cara pakai

```
agentop                 # workflow terbaru (dari kedua akar config)
agentop wf_e63f8578      # run tertentu, prefix ID cukup
agentop -i 2             # ganti interval refresh, default 1 detik
agentop -v               # atau --version, cetak versi lalu keluar
```

Variabel lingkungan `AGENTOP_HOME` menimpa akar config yang dipindai (default: home directory pengguna, tempat `.claude` dan `.claude-work` dicari). Berguna untuk mengarahkan agentop ke direktori hasil capture tanpa workflow live yang jalan; ini juga cara test menjalankan agentop terhadap fixture.

### Peta tombol

Panel yang bisa difokuskan cuma dua: runs (daftar run) dan agents (daftar agent dalam run terpilih). Transcript agent bukan panel, melainkan layar tersendiri yang dibuka lewat Enter.

| Tombol | Aksi |
|---|---|
| `Tab` / `→` / `l` | pindah fokus ke panel lain (runs ⇄ agents) |
| `Shift+Tab` / `←` / `h` | pindah fokus ke panel lain, arah sebaliknya |
| `↑`/`↓` atau `j`/`k` | gerak dalam panel yang sedang fokus |
| `Enter` | di panel runs: pindah fokus ke panel agents. Di panel agents: buka transcript agent yang dipilih |
| `Esc` | di layar transcript atau layar bantuan: kembali ke daftar. Di layar daftar: tidak berbuat apa-apa |
| `f` | tampilkan cuma agent yang gagal/masih berjalan |
| `r` | refresh sekarang, tanpa menunggu interval |
| `?` | buka bantuan; dari layar bantuan, `?`/`Enter`/`Esc` sama-sama menutupnya |
| `q` / `Ctrl+C` | keluar |

## Catatan keamanan

agentop hanya membaca berkas, tidak pernah menulis ke direktori config Claude Code. Aman dijalankan berdampingan dengan workflow yang sedang berjalan; tidak ada risiko race condition terhadap Claude Code sendiri.

## Rilis

Rilis dipublikasikan lewat [GoReleaser](https://goreleaser.com) yang terpicu otomatis saat tag `v*` di-push, mem-build binary darwin+linux+windows (amd64+arm64), menerbitkan GitHub Release ke repo publik `pimlabs/agentop`, cask ke tap `pimlabs/homebrew-tap`, dan paket ke npm di bawah scope `@pimlabs`. Detail lengkap ada di [RELEASING.md](RELEASING.md).
