# NAT VPS AIO Panel v1.0

Panel bash untuk NAT VPS dengan IP publik yang dapat berubah.

## Fitur

- Menu interaktif ala AutoScriptVPN-AIO
- Status SSH, Nginx, Xray, WireGuard
- Xray VLESS TCP
- WireGuard
- Nginx
- SSH
- Deteksi public/local IP
- Domain/DDNS
- Cloudflare DDNS updater
- Auto update DDNS via systemd timer setiap 5 menit
- Restart service
- System info
- NAT/port information

## Instalasi

Login ke VPS sebagai root, lalu:

```bash
apt update -y
apt install -y curl wget ca-certificates
wget -O setup.sh https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/setup.sh
chmod +x setup.sh
sed -i -e 's/\r$//' setup.sh
./setup.sh
```

Ganti `USERNAME/REPOSITORY` dengan repository GitHub milikmu.

Setelah selesai:

```bash
nat-vps-aio
```

## Jika ingin langsung dari file

```bash
chmod +x setup.sh
./setup.sh
nat-vps-aio
```

## IP sering berubah

Gunakan domain/DDNS. Panel menyediakan integrasi Cloudflare DDNS.

Masuk menu:

`[6] Cloudflare DDNS`

Isi:
- API Token
- Zone ID
- DNS Record ID
- nama record, misalnya `vpn.example.com`

Setelah itu record A akan diperbarui berkala.

## Penting untuk NAT VPS

Script tidak dapat membuat port publik sendiri. Provider NAT harus memberikan port-forward/mapping ke VPS.

Contoh:

```text
IP publik provider:PORT  --->  IP private VPS:PORT
```

Jika provider mengganti port mapping, mapping baru harus disesuaikan di panel/provider.

## Keamanan

- Jangan membagikan Cloudflare API Token.
- Jangan membagikan private key WireGuard.
- Jangan membuka port yang tidak diperlukan.
- Gunakan domain/DDNS jika IP publik berubah.
- Gunakan hanya pada VPS dan jaringan yang kamu miliki/berwenang mengelola.

Xray dipasang menggunakan installer resmi yang dirujuk oleh dokumentasi Xray-core.
