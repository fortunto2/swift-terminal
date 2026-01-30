import Foundation

/// Shell script templates for VPS provisioning.
public enum ProvisioningScripts {
    /// Get the provisioning script for a feature.
    public static func script(
        for feature: ProvisioningFeature,
        username: String = "deploy",
        sshPort: Int = 2222
    ) -> String {
        switch feature {
        case .securityHardening:
            securityHardening(username: username, sshPort: sshPort)
        case .claudeCode:
            claudeCodeInstall
        case .devTools:
            devToolsInstall
        case .docker:
            dockerInstall
        case .uv:
            uvInstall
        case .bun:
            bunInstall
        }
    }

    /// Get all scripts for a provisioning config, concatenated.
    public static func fullScript(for config: ProvisioningConfig) -> String {
        let header = """
        #!/bin/bash
        set -euo pipefail

        # ============================================
        # SwiftTerminal — VPS Provisioning Script
        # Generated: \(ISO8601DateFormatter().string(from: .now))
        # Hostname: \(config.hostname)
        # Features: \(config.features.map(\.displayName).joined(separator: ", "))
        # ============================================

        export DEBIAN_FRONTEND=noninteractive
        echo "🚀 Starting provisioning for \(config.hostname)..."

        """

        let scripts = config.features.map { feature in
            """
            # ── \(feature.displayName) ──
            \(script(for: feature, username: config.deployUsername, sshPort: config.sshPort))
            """
        }

        let footer = """

        echo ""
        echo "🏁 Provisioning complete!"
        echo "   User: \(config.deployUsername)"
        echo "   SSH Port: \(config.sshPort)"
        echo "   Hostname: \(config.hostname)"
        """

        return header + scripts.joined(separator: "\n\n") + footer
    }

    // MARK: - Individual Scripts

    /// Security hardening: create deploy user, harden SSH, install fail2ban, configure UFW.
    public static func securityHardening(username: String = "deploy", sshPort: Int = 2222) -> String {
        """
        echo "🔒 Security Hardening..."

        # Update system
        apt-get update -qq && apt-get upgrade -y -qq

        # Create deploy user with sudo
        if ! id "\(username)" &>/dev/null; then
            useradd -m -s /bin/bash -G sudo "\(username)"
            echo "\(username) ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/\(username)
            chmod 0440 /etc/sudoers.d/\(username)
            echo "  ✅ User '\(username)' created with sudo"
        else
            echo "  ℹ️  User '\(username)' already exists"
        fi

        # Copy SSH authorized_keys to new user
        if [ -d /root/.ssh ]; then
            mkdir -p /home/\(username)/.ssh
            cp /root/.ssh/authorized_keys /home/\(username)/.ssh/ 2>/dev/null || true
            chown -R \(username):\(username) /home/\(username)/.ssh
            chmod 700 /home/\(username)/.ssh
            chmod 600 /home/\(username)/.ssh/authorized_keys 2>/dev/null || true
            echo "  ✅ SSH keys copied to \(username)"
        fi

        # SSH Hardening
        SSHD_CONFIG="/etc/ssh/sshd_config"
        cp "$SSHD_CONFIG" "$SSHD_CONFIG.bak"

        sed -i 's/^#\\?Port .*/Port \(sshPort)/' "$SSHD_CONFIG"
        sed -i 's/^#\\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"
        sed -i 's/^#\\?PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CONFIG"
        sed -i 's/^#\\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        sed -i 's/^#\\?X11Forwarding .*/X11Forwarding no/' "$SSHD_CONFIG"
        sed -i 's/^#\\?MaxAuthTries .*/MaxAuthTries 3/' "$SSHD_CONFIG"

        echo "  ✅ SSH hardened (port \(sshPort), root disabled, password auth disabled)"

        # Install and configure fail2ban
        apt-get install -y -qq fail2ban
        cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
        [sshd]
        enabled = true
        port = \(sshPort)
        filter = sshd
        logpath = /var/log/auth.log
        maxretry = 5
        bantime = 3600
        findtime = 600
        FAIL2BAN
        systemctl enable fail2ban
        systemctl restart fail2ban
        echo "  ✅ fail2ban installed and configured"

        # Setup UFW firewall
        apt-get install -y -qq ufw
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow \(sshPort)/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        echo "y" | ufw enable
        echo "  ✅ UFW firewall configured (SSH \(sshPort), HTTP 80, HTTPS 443)"

        # Restart SSH (do this last!)
        systemctl restart sshd
        echo "  ✅ SSH restarted on port \(sshPort)"

        echo "🔒 Security hardening complete!"
        echo "⚠️  IMPORTANT: Reconnect using port \(sshPort) as user '\(username)'"
        """
    }

    /// Install Claude Code CLI.
    public static var claudeCodeInstall: String {
        """
        echo "🧠 Installing Claude Code..."

        # Install Node.js (required for Claude Code)
        if ! command -v node &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y -qq nodejs
            echo "  ✅ Node.js $(node --version) installed"
        else
            echo "  ℹ️  Node.js $(node --version) already installed"
        fi

        # Install Claude Code
        curl -fsSL https://claude.ai/install.sh | bash
        echo "  ✅ Claude Code installed"

        # Add to PATH for all users
        if [ -f /usr/local/bin/claude ]; then
            echo "  ✅ Claude Code available at /usr/local/bin/claude"
        fi

        # Install companion tools
        apt-get install -y -qq ripgrep tmux git
        echo "  ✅ ripgrep, tmux, git installed"

        echo "🧠 Claude Code installation complete!"
        """
    }

    /// Install dev tools (ripgrep, tmux, git, etc.).
    public static var devToolsInstall: String {
        """
        echo "🛠️ Installing dev tools..."

        apt-get update -qq
        apt-get install -y -qq \\
            ripgrep \\
            tmux \\
            git \\
            curl \\
            wget \\
            htop \\
            jq \\
            tree \\
            unzip \\
            build-essential

        echo "  ✅ Core dev tools installed"

        # Setup tmux config
        cat > /etc/skel/.tmux.conf << 'TMUX'
        set -g mouse on
        set -g history-limit 50000
        set -g default-terminal "screen-256color"
        set -ga terminal-overrides ",xterm-256color:Tc"
        set -g status-style "bg=black,fg=white"
        set -g base-index 1
        setw -g pane-base-index 1
        TMUX
        echo "  ✅ tmux configured"

        echo "🛠️ Dev tools installation complete!"
        """
    }

    /// Install Docker Engine and Docker Compose.
    public static var dockerInstall: String {
        """
        echo "🐳 Installing Docker..."

        if ! command -v docker &>/dev/null; then
            curl -fsSL https://get.docker.com | bash
            echo "  ✅ Docker installed"
        else
            echo "  ℹ️  Docker already installed"
        fi

        # Add deploy user to docker group (if user exists)
        usermod -aG docker deploy 2>/dev/null || true

        # Enable and start Docker
        systemctl enable docker
        systemctl start docker

        # Install Docker Compose plugin
        apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
        echo "  ✅ Docker Compose installed"

        echo "🐳 Docker installation complete!"
        echo "   Docker version: $(docker --version)"
        """
    }

    /// Install uv (fast Python package manager).
    public static var uvInstall: String {
        """
        echo "⚡ Installing uv..."

        curl -LsSf https://astral.sh/uv/install.sh | bash
        echo "  ✅ uv installed"

        # Add to PATH
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> /etc/profile.d/uv.sh
        echo "  ✅ uv added to PATH"

        echo "⚡ uv installation complete!"
        """
    }

    /// Install Bun (fast JavaScript runtime).
    public static var bunInstall: String {
        """
        echo "🍞 Installing Bun..."

        curl -fsSL https://bun.sh/install | bash
        echo "  ✅ Bun installed"

        # Add to PATH
        echo 'export BUN_INSTALL="$HOME/.bun"' >> /etc/profile.d/bun.sh
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> /etc/profile.d/bun.sh
        echo "  ✅ Bun added to PATH"

        echo "🍞 Bun installation complete!"
        """
    }
}
