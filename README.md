# ready2dev
From clean OS to coding-ready in minutes.


cd && mkdir -p resources && cd resources && sudo apt update && sudo apt install -y wl-clipboard xclip && rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub && ssh-keygen -t ed25519 -C "your_email" -f ~/.ssh/id_ed25519 -N "" -q && echo -e "\n🔑 SSH Key Generated:\n" && cat ~/.ssh/id_ed25519.pub && echo && (wl-copy < ~/.ssh/id_ed25519.pub 2>/dev/null || xclip -selection clipboard < ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub | clip.exe 2>/dev/null) && echo "✅ SSH key copied to clipboard." && echo -e "\n📋 Add this key to GitHub, then press Enter to continue..." && read && git clone git@github.com:artoria026/ready2dev.git && cd ready2dev && chmod +x install.sh && ./install.sh

Instalación recomendada:
- Los scripts y aliases de Ready2Dev se alojan en ~/.local/share/ready2dev para no llenar el home con carpetas visibles.
- Mantén carpetas de propósito claro como ~/projects, ~/backups y ~/docker.
