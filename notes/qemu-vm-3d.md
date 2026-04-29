# QEMU/libvirt VM with 3D acceleration on this host

This host runs NVIDIA proprietary on X11 as the primary GPU plus an AMD iGPU as a secondary render node. That combination breaks the "obvious" SPICE-GL passthrough path. Below is the configuration that actually works, and what each piece is for.

## TL;DR config

In the libvirt domain XML (`virsh edit <name>`):

```xml
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  ...
  <devices>
    ...
    <graphics type='spice'>
      <listen type='none'/>
      <image compression='off'/>
    </graphics>
    <graphics type='egl-headless'>
      <gl rendernode='/dev/dri/by-path/pci-0000:79:00.0-render'/>
    </graphics>
    ...
    <video>
      <model type='virtio' heads='1' primary='yes'>
        <acceleration accel3d='yes'/>
      </model>
    </video>
    ...
  </devices>
  <qemu:commandline>
    <qemu:env name='__EGL_VENDOR_LIBRARY_FILENAMES' value='/usr/share/glvnd/egl_vendor.d/50_mesa.json'/>
  </qemu:commandline>
</domain>
```

The render node path is the AMD iGPU. Verify with `cat /sys/class/drm/renderD128/device/uevent` — the one with `DRIVER=amdgpu` is the right one.

In `/etc/libvirt/qemu.conf`, ensure `cgroup_device_acl` includes the NVIDIA nodes and `udmabuf` (libvirt's default sandbox blocks them):

```
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm",
    "/dev/rtc", "/dev/hpet",
    "/dev/udmabuf",
    "/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-modeset",
    "/dev/nvidia-uvm", "/dev/nvidia-uvm-tools",
    "/dev/dri/renderD128", "/dev/dri/renderD129"
]
```

Restart with `sudo systemctl restart libvirtd`.

## Verifying acceleration in the guest

```
glxinfo | grep -E "OpenGL renderer|direct rendering"
```

Expected:
```
direct rendering: Yes
OpenGL renderer string: virgl (AMD Ryzen 9 9950X 16-Core Processor (radeonsi, ...))
```

If it shows `llvmpipe` or `softpipe`, the guest is on software rendering — something in the chain failed.

Benchmarks: `glxgears` will sit around 100 fps (vsync-locked) — that doesn't measure anything useful. Use `glmark2` instead; expect a score in the low-to-mid hundreds. Pure software rendering scores in the single digits.

## Why each piece is needed

### `__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json`

The host has both Mesa (for AMD) and NVIDIA EGL vendor libraries installed. libglvnd dispatches EGL to the NVIDIA vendor by default because NVIDIA is the primary GPU. When QEMU opens the AMD render node, NVIDIA EGL fails to drive it (`EGL_NOT_INITIALIZED`). Pinning to Mesa forces EGL to use the right backend for `/dev/dri/renderD128`.

### `cgroup_device_acl` in `qemu.conf`

libvirt confines QEMU's accessible device nodes via cgroup + a per-VM `/dev` mount namespace. The default allowlist excludes `/dev/nvidia*` and `/dev/udmabuf`. Even though those nodes are world-readable, QEMU can't `open()` them from inside the sandbox, so EGL/GBM init fails (`EGL_BAD_ALLOC`) or venus init fails. Adding them to `cgroup_device_acl` is required.

### `egl-headless` + plain SPICE (no `gl=on` on SPICE)

NVIDIA's X11 driver does not expose **DRI3 modifiers**, which is what SPICE GL passthrough (DMA-buf zero-copy from QEMU to the SPICE client) requires. With `<gl enable='yes' .../>` on `<graphics type='spice'>`, the client (virt-manager / virt-viewer) running in the host's NVIDIA X session imports a DMA-buf produced by AMD GBM into NVIDIA GL — that import silently no-ops, leaving the cursor visible and the entire framebuffer black.

The workaround is a separate `<graphics type='egl-headless'>` block. egl-headless is not a user-facing display; it's a second display backend that exists purely to give QEMU an EGL context. virtio-vga-gl needs *some* display backend with GL in order to initialize ("The display backend does not have OpenGL support enabled" otherwise). egl-headless provides that. SPICE then delivers the rendered framebuffer through normal SPICE channels (no DMA-buf), which works on any host.

Order matters: put `<graphics type='spice'>` **first**. virt-manager and `virsh domdisplay` pick the first `<graphics>` block; with egl-headless first, they land on it and you get "Cannot display graphical console type 'egl-headless'". QEMU finds GL via egl-headless regardless of order.

### Cost

Without DMA-buf passthrough, every frame is read back from the host AMD GPU to CPU memory, encoded by SPICE, and decoded by the viewer. glxgears caps around 100 fps; glmark2 scores are reduced. The guest's *rendering* is fully GPU-accelerated — it's only the host→client *delivery* that is the bottleneck. Fine for desktop work and most 3D apps; not great for high-fps gaming.

To remove that ceiling, run virt-manager from a **Wayland** session on the host (Plasma Wayland with NVIDIA-open works). Wayland exposes DRI3 modifiers natively, so you can re-enable `gl=on` on SPICE and remove the egl-headless block, getting zero-copy passthrough with thousands of fps.

## Things that did not work, and why

| Attempt | Result | Reason |
|---|---|---|
| SPICE `gl=on` with NVIDIA render node | QEMU error: `EGL_NOT_INITIALIZED` | NVIDIA EGL grabbed by libglvnd; can't drive AMD node, doesn't have a usable GBM platform for QEMU's purpose |
| SPICE `gl=on` with AMD render node, no Mesa pin | Same `EGL_NOT_INITIALIZED` | Same — Mesa pin needed to force the right vendor |
| venus (Vulkan-passthrough virtio-vga-gl) | `failed to initialize venus renderer` | virglrenderer 1.2 venus + NVIDIA-open 590 + QEMU 10.2 — combination didn't work on this host |
| SPICE `gl=on` with Mesa pin, AMD render node | Cursor visible, framebuffer never reaches the viewer | NVIDIA X11 lacks DRI3 modifiers → DMA-buf import into NVIDIA GL silently fails on the client side |
| Removing `<gl>` from SPICE without adding egl-headless | QEMU error: `display backend does not have OpenGL support enabled` | virtio-vga-gl needs *some* GL-capable display backend to initialize |

## Guest-side gotchas (Ubuntu/Debian)

- The kernel module file is `virtio-gpu.ko.zst` (hyphen) but `modprobe` accepts the underscore. `/etc/initramfs-tools/modules` matches the file name literally — list it as `virtio-gpu` (with the hyphen) to get it bundled into the initramfs, otherwise the early framebuffer is missing and you get a black screen until userspace catches up.
- After adding to initramfs: `sudo update-initramfs -u`, verify with `lsinitramfs /boot/initrd.img-$(uname -r) | grep virtio-gpu`.
- Mesa packages needed in guest: `libgl1-mesa-dri`, `mesa-utils` (for `glxinfo`), `mesa-vulkan-drivers` (optional, for Vulkan via virgl).

## Useful diagnostics

Inside the guest:
```
lspci -k | grep -A3 -i vga                        # driver should be virtio-pci using virtio_gpu
ls /dev/dri/                                      # should show card1 + renderD128
glxinfo | grep -E "OpenGL renderer|direct rendering"
```

On the host, when something fails:
```
sudo tail -120 /var/log/libvirt/qemu/<name>.log   # QEMU's stderr — egl: ... lines tell you exactly which init step failed
```
