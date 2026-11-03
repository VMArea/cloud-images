# Windows images

Build scripts for Windows Server 2019, 2022 and 2025. The images are built from Microsoft Evaluation media and are never published. Only the scripts live here; licensing of the resulting images is the customer's responsibility.

## What the build does

- Downloads the Evaluation ISO from Microsoft, VirtIO drivers pinned to 0.1.271, and the latest stable Cloudbase-Init MSI. Apps listed in `apps.yaml` are fetched at build time and checked against the release digest or the Authenticode signature.
- Drives QEMU directly (OVMF, q35, virtio-scsi, virtio-net, swtpm for TPM, secure boot where the recipe asks for it). No Packer.
- Installs unattended from `files/Autounattend.xml` on a second ISO. Partitions are EFI, MSR and C: last, so no recovery partition sits behind C:. Storage and network drivers load in the windowsPE pass.
- Installs the VirtIO guest tools and the QEMU guest agent at first logon, then drives every later step through the guest agent (`guest-exec`).
- Applies Windows Update until nothing is left (time-boxed), then pins Windows Update to notify-only.
- Installs Chrome, 7-Zip and Notepad++ and removes desktop shortcuts.
- Applies the baseline in `files/scripts/baseline.ps1`: RDP with NLA, firewall rules for RDP and ICMP echo, account lockout off, Defender real-time protection off, high performance power plan, hibernation off, UTC, Server Manager and Shutdown Event Tracker prompts off. The same script runs again at first boot (SetupComplete and Cloudbase-Init LocalScripts).
- Installs Cloudbase-Init (config drive metadata, `Administrator`, password injection, long host names, network config, volume extend), removes the build user, answer files, logs and temp files, then runs `sysprep /generalize /oobe /shutdown /mode:vm`.
- Writes `output/windows-<version>-<YYYYMMDD>.qcow2`, a `.sha256` file, a `.json` manifest and an unpublished `.secrets.json` with the build passwords, used only by the test to prove none remain in the image.

## Usage

```
windows/build windows/os/server-2022.yaml
windows/test output/windows-2022-<date>.qcow2
```

Needs Linux with KVM, qemu-system-x86, qemu-utils, ovmf, swtpm, genisoimage, python3 with PyYAML, and freerdp3-x11 for the RDP login check. `ISO_CACHE` (default `~/iso`) holds the downloaded media. `--resume` continues a build from the last finished phase, `--keep` keeps the work directory.

## Test

The test boots the image on a copy-on-write overlay grown to 60G with a config drive (label `config-2`, `openstack/latest/meta_data.json` with `admin_pass`, a 25 character host name, DHCP network). It checks Cloudbase-Init, host name, disk extension, network, guest agent commands, RDP, firewall, lockout, power plan, policies, installed apps, absence of build traces, then boots again with a new instance id and password to prove a reset. `--cpu x86-64-v3` or `--cpu host` selects the CPU type.

## Results (2026-11-01)

| Image | Build | Cumulative update | Test |
|---|---|---|---|
| Windows Server 2019 | 17763.9376 | KB5126651, .NET KB5127685 and KB5127666 | 54 passed, 0 failed (host CPU) |
| Windows Server 2022 | 20348.5761 | KB5126655, .NET KB5127693 and KB5127687 | 54 passed, 0 failed (host CPU) |
| Windows Server 2025 | 26100.33650 | KB5043080 checkpoint, KB5126646, .NET KB5127690 | 55 passed, 0 failed on both a v3-flag CPU and host |

QEMU 8.2 has no named `x86-64-v3` model, so the 2025 test uses `qemu64` with the v3 feature flags. Setup itself does not run on that model (error 0x800706BA), so 2025 is built on `host`. The 2019 cumulative update is installed with `wusa` because DISM 10.0.17763 rejects the package (error 50).

## Server 2025 first logon (2026-11-02)

Cause: sysprep was started through the guest agent, which runs as Local System. Microsoft documents that sysprep run as Local System skips AppX registration of XAML shell packages (Client.CBS, Client.Core, Microsoft.UI.Xaml.CBS) and Explorer then fails on first logon. The dump of the crashed Explorer (10.0.26100.33648) shows a fail-fast (0xc0000409, FAST_FAIL_FATAL_APP_EXIT, HRESULT 0x8000FFFF) in `explorer!CTray::Init` (tray.cpp line 737) right after `XamlExtensions.IsExtensionAvailable("WindowsUdk.UI.Shell.TaskbarControllerExtension", "Taskbar")` returned false. The extension is declared by MicrosoftWindows.Client.Core. Only the first logon on the machine crashed; a second user right after was fine.

Not the cause: the deprecated SkipMachineOOBE/SkipUserOOBE settings (removed, still 3 of 3 crashes), waiting up to 20 minutes before the first logon, policies, the cumulative update, the apps and cleanup.

Fix: the build starts sysprep as Administrator through a one-shot scheduled task (removed as soon as sysprep is running), with the stock `explorer.exe` shell. 3 of 3 first logons then gave a taskbar and no crash.

`windows/build --stop-after <phase>` halts a build after a phase so the disk can be copied and tested, which is how the cause was bisected.
