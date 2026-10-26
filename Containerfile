# syntax=docker/dockerfile:1
ARG OS_IMAGE=registry.opensuse.org/opensuse/leap
ARG OS_VERSION=16.0

# 直接以目标操作系统为基础镜像，不再需要 ghcr 的 toolkit 阶段
FROM ${OS_IMAGE}:${OS_VERSION}

ARG REPO=ghcr.io/your-org/my-wayland-opensuse-lite-vm
ARG VERSION=latest

ENV REPO=${REPO}
ENV VERSION=${VERSION}

# 1. 补充 openSUSE Leap 16.0 官方与 M17N 字体社区源
RUN zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/distribution/leap/16.0/repo/oss/ oss || true && \
    zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/distribution/leap/16.0/repo/non-oss/ non-oss || true && \
    zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/repositories/M17N:/fonts/16.0/ M17N-fonts || true

# 2. 自动信任导入 GPG 密钥并刷新源缓存
RUN zypper --non-interactive --gpg-auto-import-keys refresh

# 3. 安装核心软件，直接包含官方源最新版的 elemental-toolkit
RUN ARCH=$(uname -m); \
    ADD_PKGS=""; \
    if [ "${ARCH}" != "riscv64" ]; then \
        ADD_PKGS+=" shim"; \
        [ "${ARCH}" = "aarch64" ] && ARCH="arm64"; \
    fi; \
    zypper --non-interactive --gpg-auto-import-keys install --no-recommends -- \
        ${ADD_PKGS} \
        audit \
        btop \
        btrfsmaintenance \
        btrfsprogs \
        curl \
        device-mapper \
        dosfstools \
        dracut \
        e2fsprogs \
        elemental-toolkit \
        fastfetch \
        featherpad \
        findutils \
        fontconfig \
        gedit \
        gptfdisk \
        grim \
        grub2 \
        grub2-${ARCH}-efi \
        gzip \
        haveged \
        htop \
        iproute2 \
        kanshi \
        kate \
        kernel-default \
        konsole \
        labwc \
        less \
        lvm2 \
        lxqt-labwc-session \
        lxqt-session \
        lxqt-wayland-session \
        meld \
        Mesa \
        Mesa-dri \
        mtools \
        NetworkManager \
        noto-sans-cjk-fonts \
        openbox \
        openssh-clients \
        openssh-server \
        open-vm-tools \
        open-vm-tools-desktop \
        parted \
        patterns-lxqt-lxqt \
        pcmanfm-qt \
        podman \
        python3 \
        qt6-wayland \
        qterminal \
        rsync \
        screengrab \
        sddm \
        sed \
        slurp \
        snapper \
        squashfs \
        sudo \
        swaybg \
        syncthing \
        systemd \
        tar \
        tilix \
        timezone \
        uv \
        vim \
        wdisplays \
        which \
        wl-clipboard \
        wlr-randr \
        wqy-microhei-fonts \
        xorriso \
        xterm-resize \
        xwayland && \
    fc-cache -f && \
    zypper clean --all

# 4. 基础用户与免密 sudo 配置 (liveuser 与 peter)
RUN groupadd -f wheel && \
    useradd -m -G wheel -s /bin/bash liveuser && \
    echo "liveuser:liveuser" | chpasswd && \
    useradd -m -G wheel -s /bin/bash peter && \
    echo "peter:peter" | chpasswd && \
    echo "root:root" | chpasswd && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/sudoers

# ----------------------------------------------------
# 5. 固化 Elemental 分区配置（Btrfs 原生快照）
# ----------------------------------------------------
RUN mkdir -p /etc/elemental && \
    printf 'install:\n  snapshotter:\n    type: btrfs\n  partitions:\n    recovery:\n      size: 8192\n      filesystem: btrfs\n    state:\n      size: 30720\n      filesystem: btrfs\n    persistent:\n      size: 0\n      filesystem: btrfs\n' > /etc/elemental/config.yaml

# ----------------------------------------------------
# 6. 注入持久化目录初始化脚本与 Systemd 服务 (解决空寻址与桌面失忆)
# ----------------------------------------------------
RUN mkdir -p /usr/local/bin && \
    printf '#!/bin/bash\nPERSISTENT_HOME="/run/elemental/persistent/home/peter"\nPERSISTENT_ROOT="/run/elemental/persistent/root"\nif [ ! -d "$PERSISTENT_HOME" ]; then\n    mkdir -p "$PERSISTENT_HOME/.config/lxqt"\n    mkdir -p "$PERSISTENT_ROOT"\n    cp -a /etc/skel/. "$PERSISTENT_HOME/" || true\n    printf "[General]\\nwindow_manager=labwc\\nleave_confirmation=true\\n\\n[Wayland]\\ncompositor=labwc\\nscreen_locker=swaylock\\n" > "$PERSISTENT_HOME/.config/lxqt/session.conf"\n    chown -R peter:peter "$PERSISTENT_HOME"\nfi\n' > /usr/local/bin/init-persistent-home.sh && \
    chmod +x /usr/local/bin/init-persistent-home.sh

RUN printf '[Unit]\nDescription=Initialize Persistent Home Directory structure for Elemental\nDefaultDependencies=no\nAfter=run-elemental-persistent.mount\nBefore=local-fs.target home.mount\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/init-persistent-home.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=local-fs.target\n' > /etc/systemd/system/init-persistent-home.service

RUN systemctl enable init-persistent-home.service

# RUN systemctl enable init-persistent-home.service && \
#     printf '/run/elemental/persistent/home /home none bind,x-systemd.requires-mounts-for=/run/elemental/persistent 0 0\n/run/elemental/persistent/root /root none bind,x-systemd.requires-mounts-for=/run/elemental/persistent 0 0\n' >> /etc/fstab

# ------------------------------
# 7. 固化 SDDM 默认显示管理器与系统启动目标软链接
# ------------------------------
RUN mkdir -p /etc/sysconfig /etc/systemd/system/graphical.target.wants && \
    echo 'DISPLAYMANAGER="sddm"' > /etc/sysconfig/displaymanager && \
    systemctl set-default graphical.target && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/graphical.target.wants/sddm.service

# ------------------------------
# 8. 启用服务并执行 Elemental 初始化
# ------------------------------
RUN systemctl enable vmtoolsd.service || systemctl enable open-vm-tools.service || true && \
    systemctl enable NetworkManager.service || true && \
    systemctl enable sshd.service || true && \
    systemctl enable sddm.service || true && \
    systemd-sysusers || true && \
    mkdir -p /var/tmp /var/log /run/lock /etc/dracut.conf.d /etc/elemental && \
    echo 'hostonly="no"' > /etc/dracut.conf.d/02-generic.conf && \
    KERNEL_FILE=$(ls -1 /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | head -n 1) && \
    if [ -n "${KERNEL_FILE}" ] && [ ! -e /boot/vmlinuz ]; then \
        ln -sf "${KERNEL_FILE}" /boot/vmlinuz; \
    fi && \
    elemental --debug init --force

# 9. 写入元数据至 /etc/os-release
RUN echo "IMAGE_REPO=\"${REPO}\"" >> /etc/os-release && \
    echo "IMAGE_TAG=\"${VERSION}\"" >> /etc/os-release && \
    echo "IMAGE=\"${REPO}:${VERSION}\"" >> /etc/os-release && \
    echo "TIMESTAMP=\"$(date +'%Y%m%d%H%M%S')\"" >> /etc/os-release && \
    echo "GRUB_ENTRY_NAME=\"my-wayland-opensuse-lite-vm\"" >> /etc/os-release
