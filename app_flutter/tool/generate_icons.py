"""一键生成全平台 App 图标。

数据源：assets/icon/source.png（高清原图）
输出：
  - android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
  - web/favicon.png, web/icons/Icon-192.png, web/icons/Icon-512.png
  - windows/runner/resources/app_icon.ico
  - assets/icon/app_icon.png  (Flutter 资源)

用法：
  python tool/generate_icons.py
"""
from __future__ import annotations

import os
import urllib.request
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
SRC = os.path.join(ROOT, "assets", "icon", "source.png")

# 高清原图（带 UCloud 签名，会过期，首次运行后已落盘，可删除此常量）
SOURCE_URL = (
    "https://maas-log-prod.cn-wlcb.ufileos.com/anthropic/"
    "9cb7eba6-0761-4644-8ebe-9d9cb53049d2/"
    "1a41765105685c047655e844b518be12.png"
    "?UCloudPublicKey=TOKEN_e15ba47a-d098-4fbd-9afc-a0dcf0e4e621"
    "&Expires=1783431152&Signature=aB60OzmL+D47H2eSxWXE7yK/GIo="
)

ANDROID = {
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
}

WEB = {
    "web/favicon.png": 32,
    "web/icons/Icon-192.png": 192,
    "web/icons/Icon-512.png": 512,
}

ASSET_ICON = ("assets/icon/app_icon.png", 1024)

# Windows .ico 多尺寸
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
ICO_PATH = "windows/runner/resources/app_icon.ico"


def ensure_source() -> Image.Image:
    if os.path.exists(SRC):
        print(f"[skip] 已存在本地原图：{SRC}")
        return Image.open(SRC).convert("RGBA")
    print(f"[get ] 下载原图 → {SRC}")
    os.makedirs(os.path.dirname(SRC), exist_ok=True)
    req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(SRC, "wb") as f:
        f.write(r.read())
    return Image.open(SRC).convert("RGBA")


def resize_to(src: Image.Image, size: int) -> Image.Image:
    return src.resize((size, size), Image.LANCZOS)


def main() -> None:
    src = ensure_source()
    print(f"[info] 原图尺寸：{src.size} 模式：{src.mode}")

    for rel, size in {**ANDROID, **WEB}.items():
        out = os.path.join(ROOT, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        resize_to(src, size).save(out, "PNG")
        print(f"[ok  ] {rel}  {size}x{size}")

    rel, size = ASSET_ICON
    out = os.path.join(ROOT, rel.replace("/", os.sep))
    resize_to(src, size).save(out, "PNG")
    print(f"[ok  ] {rel}  {size}x{size}")

    # Windows ico：用最大尺寸作为基准，Pillow 自动生成多尺寸
    ico_out = os.path.join(ROOT, ICO_PATH.replace("/", os.sep))
    os.makedirs(os.path.dirname(ico_out), exist_ok=True)
    resize_to(src, 256).save(
        ico_out,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
    )
    print(f"[ok  ] {ICO_PATH}  多尺寸 {ICO_SIZES}")

    print("\n完成。下一步：flutter clean && flutter run 重新构建即可生效。")


if __name__ == "__main__":
    main()
