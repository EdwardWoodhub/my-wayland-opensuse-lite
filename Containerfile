# syntax=docker/dockerfile:1
ARG OS_IMAGE=registry.opensuse.org/opensuse/leap
ARG OS_VERSION=16.0

# 第一阶段：获取官方 elemental-toolkit CLI 与 dracut 模块
FROM ghcr.io/rancher/elemental-toolkit/elemental-cli:latest AS toolkit

# 第二阶段：构建目标操作系统镜像
FROM ${OS_IMAGE}:${OS_VERSION}

ARG REPO=ghcr.io/your-org/my-wayland-opensuse-lite-vm
ARG VERSION=latest

ENV REPO=${REPO}
ENV VERSION=${VERSION}

# 2. 补充 openSUSE Leap 16.0 官方与 M17N 字体社区源
RUN zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/distribution/leap/16.0/repo/oss/ oss || true && \
    zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/distribution/leap/16.0/repo/non-oss/ non-oss || true && \
    zypper --non-interactive ar -cf -p 90 https://download.opensuse.org/repositories/M17N:/fonts/16.0/ M17N-fonts || true

# 3. 自动信任导入 GPG 密钥并刷新源缓存
RUN zypper --non-interactive --gpg-auto-import-keys refresh

# 1. 安装核心引导、内核、驱动、中文字体与 LXQt + labwc 桌面环境
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

# 2. 注入 elemental 二进制工具及专用的 dracut 模块
COPY --from=toolkit /usr/bin/elemental /usr/bin/elemental
COPY --from=toolkit /usr/lib/dracut/modules.d/ /usr/lib/dracut/modules.d/

# ------------------------------
# 1. 基础用户与免密 sudo 配置 (liveuser 与 peter)
# ------------------------------
RUN groupadd -f wheel && \
    useradd -m -G wheel -s /bin/bash liveuser && \
    echo "liveuser:liveuser" | chpasswd && \
    useradd -m -G wheel -s /bin/bash peter && \
    echo "peter:peter" | chpasswd && \
    echo "root:root" | chpasswd && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/sudoers

# ----------------------------------------------------
# 固化 Elemental 分区配置（persistent 自动吃满剩余空间）与目录持久化规则
# ----------------------------------------------------
RUN mkdir -p /etc/elemental && \
    printf 'install:\n  snapshotter:\n    type: btrfs\n  partitions:\n    recovery:\n      size: 8192\n    state:\n      size: 30720\n    persistent:\n      size: 0\n' > /etc/elemental/config.yaml && \
    printf 'dirs:\n  - /home\n  - /root\n  - /var/lib/containers\n' > /etc/elemental/persistent-dirs.yaml


# ------------------------------
# 3. 固化 SDDM 默认显示管理器与系统启动目标软链接
# ------------------------------
RUN mkdir -p /etc/sysconfig /etc/systemd/system/graphical.target.wants && \
    echo 'DISPLAYMANAGER="sddm"' > /etc/sysconfig/displaymanager && \
    systemctl set-default graphical.target && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/graphical.target.wants/sddm.service

# ------------------------------
# 4. 启用 VMware 增强工具服务
# ------------------------------
RUN systemctl enable vmtoolsd.service || systemctl enable open-vm-tools.service || true

# 3. 启用系统与桌面服务，准备配置目录与内核链接，执行 Elemental 初始化
RUN systemctl enable NetworkManager.service || true && \
    systemctl enable sshd.service || true && \
    systemctl enable sddm.service || true && \
    systemctl set-default graphical.target && \
    systemd-sysusers || true && \
    mkdir -p /var/tmp /var/log /run/lock /etc/dracut.conf.d /etc/elemental && \
    echo 'hostonly="no"' > /etc/dracut.conf.d/02-generic.conf && \
    # 确保 /boot/vmlinuz 软链接存在
    KERNEL_FILE=$(ls -1 /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | head -n 1) && \
    if [ -n "${KERNEL_FILE}" ] && [ ! -e /boot/vmlinuz ]; then \
        ln -sf "${KERNEL_FILE}" /boot/vmlinuz; \
    fi && \
    elemental --debug init --force

# 4. 写入元数据至 /etc/os-release
RUN echo "IMAGE_REPO=\"${REPO}\"" >> /etc/os-release && \
    echo "IMAGE_TAG=\"${VERSION}\"" >> /etc/os-release && \
    echo "IMAGE=\"${REPO}:${VERSION}\"" >> /etc/os-release && \
    echo "TIMESTAMP=\"$(date +'%Y%m%d%H%M%S')\"" >> /etc/os-release && \
    echo "GRUB_ENTRY_NAME=\"my-wayland-opensuse-lite-vm\"" >> /etc/os-release
