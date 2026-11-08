"""Build the app-private HDC bridge using an API 26 Windows NDK."""
import argparse
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ndk", type=Path, help="Path to the SDK native directory")
    sdk = parser.parse_args().ndk.resolve()
    source = Path(__file__).resolve().parent
    libs = source.parent / "entry" / "libs" / "arm64-v8a"
    subprocess.run([
        str(sdk / "llvm/bin/clang++.exe"), "--target=aarch64-linux-ohos",
        f"--sysroot={sdk / 'sysroot'}", "-std=c++17", "-O2", "-fPIC",
        "-fvisibility=hidden", "-shared", str(source / "private_hdc.cpp"),
        f"-L{libs}", "-lhdc_z", "-lace_napi.z", "-Wl,-z,now", "-Wl,-z,relro",
        "-Wl,-z,noexecstack", "-Wl,-soname,libhs_session.so",
        "-o", str(libs / "libhs_session.so"),
    ], check=True)


if __name__ == "__main__":
    main()
