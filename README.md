# 构建工具

Containerfile

## 基础镜像

选择SUSE的镜像更容易构建：

[Elemental - Immutable Linux for Rancher](https://elemental.docs.rancher.com/custom-images/)

选择openSUSE的镜像更容易自定义：

[Portal:Container/Base Container - openSUSE Wiki](https://en.opensuse.org/Portal:Container/Base_Container)

[How to Build Elemental OS Images](https://oneuptime.com/blog/post/2026-03-20-elemental-build-os-images/view)


# 构建产物

(1) OCI镜像

(2) 分片LiveCD


# 推送方式

本地的各个Layer Blob，直接推送到GHCR。
