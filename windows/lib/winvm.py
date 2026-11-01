import base64
import json
import os
import shutil
import socket
import subprocess
import time

OVMF_DIR = "/usr/share/OVMF"
HV = "hv_ipi,hv_relaxed,hv_reset,hv_runtime,hv_spinlocks=0x1fff,hv_stimer,hv_synic,hv_time,hv_vapic,hv_vpindex"


V3_FALLBACK = "qemu64,+ssse3,+sse4.1,+sse4.2,+popcnt,+cx16,+lahf_lm,+avx,+avx2,+fma,+bmi1,+bmi2,+f16c,+movbe,+xsave,+abm"


def cpu_model(name):
    if name == "x86-64-v3":
        out = subprocess.run(["qemu-system-x86_64", "-cpu", "help"], capture_output=True, text=True).stdout
        if "x86-64-v3" not in out:
            return V3_FALLBACK
    return name


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


class QGAError(Exception):
    pass


class QGA:
    def __init__(self, path):
        self.path = path
        self.sock = None
        self.buf = b""

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buf = b""

    def _connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(self.path)
        self.sock = s
        self.buf = b""

    def _readline(self, timeout):
        end = time.time() + timeout
        while b"\n" not in self.buf:
            left = end - time.time()
            if left <= 0:
                raise QGAError("timeout")
            self.sock.settimeout(left)
            try:
                d = self.sock.recv(65536)
            except socket.timeout:
                raise QGAError("timeout")
            if not d:
                raise QGAError("closed")
            self.buf += d
        line, self.buf = self.buf.split(b"\n", 1)
        return line

    def _sync(self, timeout=5):
        sid = int(time.time() * 1000) % 2000000000
        self.sock.sendall(b"\xff" + json.dumps({"execute": "guest-sync-delimited", "arguments": {"id": sid}}).encode() + b"\n")
        end = time.time() + timeout
        while time.time() < end:
            line = self._readline(max(0.1, end - time.time()))
            try:
                r = json.loads(line.lstrip(b"\xff"))
            except ValueError:
                continue
            if r.get("return") == sid:
                return
        raise QGAError("sync timeout")

    def call(self, cmd, args=None, timeout=30):
        try:
            if self.sock is None:
                self._connect()
                self._sync()
            req = {"execute": cmd}
            if args:
                req["arguments"] = args
            self.sock.sendall(json.dumps(req).encode() + b"\n")
            while True:
                r = json.loads(self._readline(timeout))
                if "return" in r:
                    return r["return"]
                if "error" in r:
                    raise QGAError(r["error"].get("desc", str(r["error"])))
        except (OSError, ValueError, QGAError) as e:
            self.close()
            raise QGAError(str(e))

    def ready(self):
        try:
            self.call("guest-ping", timeout=5)
            return True
        except QGAError:
            return False

    def wait_ready(self, timeout, vm=None):
        end = time.time() + timeout
        while time.time() < end:
            if vm and not vm.alive():
                raise QGAError("vm exited")
            if self.ready():
                return True
            time.sleep(5)
        return False

    def wait_gone(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if not self.ready():
                return True
            time.sleep(2)
        return False

    def exec(self, path, args=(), timeout=300):
        a = {"path": path, "arg": list(args), "capture-output": True}
        pid = self.call("guest-exec", a)["pid"]
        end = time.time() + timeout
        fails = 0
        while True:
            try:
                st = self.call("guest-exec-status", {"pid": pid}, timeout=300)
                fails = 0
            except QGAError:
                fails += 1
                if fails > 10 or time.time() > end:
                    raise
                time.sleep(5)
                continue
            if st.get("exited"):
                out = base64.b64decode(st.get("out-data", "")).decode("utf-8", "replace")
                err = base64.b64decode(st.get("err-data", "")).decode("utf-8", "replace")
                return st.get("exitcode", -1), out, err
            if time.time() > end:
                raise QGAError("exec timeout")
            time.sleep(2)

    def ps(self, script, timeout=300):
        pre = "$ProgressPreference='SilentlyContinue';[Console]::OutputEncoding=[Text.Encoding]::UTF8\n"
        enc = base64.b64encode((pre + script).encode("utf-16-le")).decode()
        if len(enc) > 24000:
            path = "C:/Windows/Temp/vm-%d.ps1" % int(time.time() * 1000)
            h = self.call("guest-file-open", {"path": path, "mode": "w"})
            data = (pre + script).encode("utf-8-sig")
            for i in range(0, len(data), 30000):
                self.call("guest-file-write", {"handle": h, "buf-b64": base64.b64encode(data[i:i + 30000]).decode()})
            self.call("guest-file-close", {"handle": h})
            return self.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path], timeout)
        return self.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", enc], timeout)

    def ps_retry(self, script, timeout=300, tries=3):
        last = None
        for _ in range(tries):
            try:
                return self.ps(script, timeout)
            except QGAError as e:
                last = e
                time.sleep(5)
        raise last


class VM:
    def __init__(self, work, disk, name="vm", ram=6144, cpus=4, cpu="host", tpm=False, secureboot=False,
                 cdroms=(), hostfwd=(), mac="52:54:00:12:34:56", fresh_vars=True, hv=True, cache="unsafe"):
        self.work = work
        self.disk = disk
        self.name = name
        self.ram = ram
        self.cpus = cpus
        self.cpu = cpu
        self.tpm = tpm
        self.secureboot = secureboot
        self.cdroms = list(cdroms)
        self.hostfwd = list(hostfwd)
        self.mac = mac
        self.fresh_vars = fresh_vars
        self.hv = hv
        self.cache = cache
        self.proc = None
        self.tpm_proc = None
        self.qmp_path = os.path.join(work, name + ".qmp")
        self.qga_path = os.path.join(work, name + ".qga")
        self.vars = os.path.join(work, name + "-vars.fd")
        self.qga = QGA(self.qga_path)

    def _vars_src(self):
        return os.path.join(OVMF_DIR, "OVMF_VARS_4M.ms.fd" if self.secureboot else "OVMF_VARS_4M.fd")

    def _code(self):
        return os.path.join(OVMF_DIR, "OVMF_CODE_4M.secboot.fd" if self.secureboot else "OVMF_CODE_4M.fd")

    def start(self):
        os.makedirs(self.work, exist_ok=True)
        for p in (self.qmp_path, self.qga_path):
            if os.path.exists(p):
                os.unlink(p)
        if self.fresh_vars or not os.path.exists(self.vars):
            shutil.copy(self._vars_src(), self.vars)
        cpu = cpu_model(self.cpu) + ("," + HV if self.hv else "")
        mach = "q35,accel=kvm" + (",smm=on" if self.secureboot else "")
        a = ["qemu-system-x86_64", "-name", self.name, "-machine", mach, "-cpu", cpu, "-smp", str(self.cpus), "-m", str(self.ram),
             "-uuid", "7b1d3c52-0000-4000-8000-000000000001", "-display", "none", "-vga", "std", "-rtc", "base=utc",
             "-qmp", "unix:%s,server=on,wait=off" % self.qmp_path,
             "-drive", "if=pflash,format=raw,unit=0,file=%s,readonly=on" % self._code(),
             "-drive", "if=pflash,format=raw,unit=1,file=%s" % self.vars]
        if self.secureboot:
            a += ["-global", "driver=cfi.pflash01,property=secure,value=on"]
        a += ["-device", "virtio-scsi-pci,id=scsi0",
              "-drive", "file=%s,if=none,id=d0,format=qcow2,discard=unmap,detect-zeroes=unmap,cache=%s" % (self.disk, self.cache),
              "-device", "scsi-hd,drive=d0,bus=scsi0.0,bootindex=%d" % (len(self.cdroms) + 1)]
        for i, c in enumerate(self.cdroms):
            a += ["-drive", "file=%s,if=none,id=c%d,media=cdrom,readonly=on,format=raw" % (c, i),
                  "-device", "ide-cd,drive=c%d,bus=ide.%d%s" % (i, i, ",bootindex=1" if i == 0 else "")]
        fwd = "".join(",hostfwd=tcp:127.0.0.1:%d-:%d" % (h, g) for h, g in self.hostfwd)
        a += ["-netdev", "user,id=n0" + fwd, "-device", "virtio-net-pci,netdev=n0,mac=%s" % self.mac]
        a += ["-device", "virtio-serial-pci", "-chardev", "socket,id=qga0,path=%s,server=on,wait=off" % self.qga_path,
              "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"]
        a += ["-device", "virtio-balloon-pci"]
        if self.tpm:
            td = os.path.join(self.work, self.name + "-tpm")
            if self.fresh_vars and os.path.exists(td):
                shutil.rmtree(td)
            os.makedirs(td, exist_ok=True)
            sock = os.path.join(td, "swtpm.sock")
            self.tpm_proc = subprocess.Popen(["swtpm", "socket", "--tpmstate", "dir=" + td, "--ctrl", "type=unixio,path=" + sock, "--tpm2",
                                              "--log", "file=" + td + "/swtpm.log"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(50):
                if os.path.exists(sock):
                    break
                time.sleep(0.1)
            a += ["-chardev", "socket,id=chrtpm,path=" + sock, "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis,tpmdev=tpm0"]
        self.args = a
        self.proc = subprocess.Popen(a, stdout=open(os.path.join(self.work, self.name + ".log"), "w"), stderr=subprocess.STDOUT)
        for _ in range(100):
            if os.path.exists(self.qmp_path):
                break
            time.sleep(0.1)

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def qmp(self, cmd, args=None):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(self.qmp_path)
        f = s.makefile("rw")
        f.readline()
        f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n")
        f.flush()
        f.readline()
        req = {"execute": cmd}
        if args:
            req["arguments"] = args
        f.write(json.dumps(req) + "\n")
        f.flush()
        while True:
            r = json.loads(f.readline())
            if "return" in r or "error" in r:
                s.close()
                return r

    def key(self, qcode):
        self.qmp("send-key", {"keys": [{"type": "qcode", "data": qcode}]})

    def screenshot(self, path):
        self.qmp("screendump", {"filename": path})

    def wait_exit(self, timeout):
        try:
            self.proc.wait(timeout)
            return True
        except subprocess.TimeoutExpired:
            return False

    def powerdown(self, timeout=120):
        try:
            self.qmp("system_powerdown")
        except OSError:
            pass
        return self.wait_exit(timeout)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        if self.tpm_proc and self.tpm_proc.poll() is None:
            self.tpm_proc.terminate()
        self.qga.close()


def ppm_to_png(src, dst):
    import struct
    import zlib
    with open(src, "rb") as f:
        data = f.read()
    parts = data.split(None, 4)
    w, h = int(parts[1]), int(parts[2])
    px = data[len(data) - w * h * 3:]
    raw = b"".join(b"\x00" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(dst, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 3)) + chunk(b"IEND", b""))
