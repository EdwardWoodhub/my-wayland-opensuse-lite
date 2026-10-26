# syntax=docker/dockerfile:1
ARG OS_IMAGE=registry.opensuse.org/opensuse/tumbleweed
ARG OS_VERSION=latest

# 第一阶段：获取官方 elemental-toolkit 完整运行资源
FROM ghcr.io/rancher/elemental-toolkit/elemental-cli:latest AS toolkit

# 第二阶段：构建目标操作系统镜像
FROM ${OS_IMAGE}:${OS_VERSION}

ARG REPO=ghcr.io/your-org/my-wayland-opensuse-lite-vm
ARG VERSION=latest

ENV REPO=${REPO}
ENV VERSION=${VERSION}

# 1. 安装核心引导、内核、驱动、中文字体与 LXQt + labwc 桌面环境
RUN ARCH=$(uname -m); \
    ADD_PKGS=""; \
    if [ "${ARCH}" != "riscv64" ]; then \
        ADD_PKGS+=" shim"; \
        [ "${ARCH}" = "aarch64" ] && ARCH="arm64"; \
    fi; \
    zypper --non-interactive removerepo repo-update || true; \
    zypper --non-interactive --gpg-auto-import-keys install --no-recommends -- \
        kernel-default \
        device-mapper \
        dracut \
        grub2 \
        grub2-${ARCH}-efi \
        haveged \
        systemd \
        NetworkManager \
        openssh-server \
        openssh-clients \
        timezone \
        parted \
        e2fsprogs \
        dosfstools \
        mtools \
        xorriso \
        findutils \
        gptfdisk \
        rsync \
        squashfs \
        lvm2 \
        tar \
        gzip \
        vim \
        which \
        less \
        sudo \
        curl \
        sed \
        iproute2 \
        podman \
        audit \
        patterns-microos-selinux \
        btrfsprogs \
        btrfsmaintenance \
        snapper \
        xterm-resize \
        htop \
        ${ADD_PKGS} \
        # --- LXQt + labwc 桌面组件 (RPM 包名) --- \
        patterns-lxqt-lxqt \
        labwc \
        lxqt-session \
        lxqt-wayland-session \
        sddm \
        wlr-randr \
        wdisplays \
        wl-clipboard \
        xwayland \
        # --- 图形驱动与中文矢量字体 --- \
        Mesa \
        Mesa-dri \
        noto-sans-cjk-fonts && \
    zypper clean --all

# 2. 完整注入 elemental 工具及其运行环境（解决 init 找不到 dracut 模块的核心）
COPY --from=toolkit /usr/bin/elemental /usr/bin/elemental
COPY --from=toolkit /usr/lib/dracut/modules.d/ /usr/lib/dracut/modules.d/
COPY --from=toolkit /usr/share/elemental/ /usr/share/elemental/
COPY --from=toolkit /etc/elemental/ /etc/elemental/

# 3. 启用系统与桌面服务，修补内核软链接，并执行 Elemental 初始化
RUN systemctl enable NetworkManager.service || true && \
    systemctl enable sshd.service || true && \
    systemctl enable sddm.service || true && \
    systemctl set-default graphical.target && \
    systemd-sysusers || true && \
    mkdir -p /var/tmp /var/log /run/lock /etc/dracut.conf.d && \
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
