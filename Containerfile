# syntax=docker/dockerfile:1
ARG OS_IMAGE=registry.opensuse.org/opensuse/tumbleweed
ARG OS_VERSION=latest

# 第一阶段：提取 elemental 命令行工具
FROM ghcr.io/rancher/elemental-toolkit/elemental-cli:latest AS toolkit

# 第二阶段：构建操作系统运行时
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
        # --- LXQt + labwc 桌面组件 (RPM包名) --- \
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

# 2. 注入 elemental 工具
COPY --from=toolkit /usr/bin/elemental /usr/bin/elemental

# 3. 启用服务、配置通用 dracut 并在隔离容器中指定准确内核版本完成初始化
RUN systemctl enable NetworkManager.service || true && \
    systemctl enable sshd.service || true && \
    systemctl enable sddm.service || true && \
    systemctl set-default graphical.target && \
    systemd-sysusers || true && \
    mkdir -p /var/tmp /var/log /run/lock /etc/dracut.conf.d && \
    echo 'hostonly="no"' > /etc/dracut.conf.d/02-generic.conf && \
    KERNEL_VERSION=$(ls /lib/modules | head -n 1) && \
    echo "Found container kernel: ${KERNEL_VERSION}" && \
    elemental --debug init --force --kernel-version "${KERNEL_VERSION}"

# 4. 写入元数据至 /etc/os-release
RUN echo "IMAGE_REPO=\"${REPO}\"" >> /etc/os-release && \
    echo "IMAGE_TAG=\"${VERSION}\"" >> /etc/os-release && \
    echo "IMAGE=\"${REPO}:${VERSION}\"" >> /etc/os-release && \
    echo "TIMESTAMP=\"$(date +'%Y%m%d%H%M%S')\"" >> /etc/os-release && \
    echo "GRUB_ENTRY_NAME=\"my-wayland-opensuse-lite-vm\"" >> /etc/os-release
