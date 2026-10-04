#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把任意图片（jpg/png/bmp...）转换成 FPGA HDMI 案例所需的原始 RGB888 数据文件。

案例要求（见 fpga_project_PARAM_UART__TO_HDMI）：
  - 分辨率   : 640 x 480  （480p）
  - 颜色格式 : RGB888（每像素 3 字节，R/G/B）
  - 总大小   : 640 * 480 * 3 = 921600 字节（不能多也不能少）
  - 存储格式 : 无文件头、无压缩的裸数据，逐行、从上到下

用法示例（Windows 下用 py 启动器）：
  py image_to_rgb888.py photo.jpg
  py image_to_rgb888.py photo.jpg -o out.rgb            # 指定输出文件名
  py image_to_rgb888.py photo.jpg --mode stretch        # 拉伸填满（默认 fit）
  py image_to_rgb888.py photo.jpg --mode crop           # 裁剪填满
  py image_to_rgb888.py photo.jpg --swap                # 若显示时红蓝颠倒则加此参数

mode 说明：
  fit     : 等比缩放并居中，多余部分补黑色             （默认，不变形不裁切）
  crop    : 等比缩放铺满，多余部分裁掉
  stretch : 直接拉伸到 640x480（会变形但无黑边）
"""

import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("缺少 Pillow，请先运行：py -m pip install Pillow")

W = 640
H = 480
RAW_SIZE = W * H * 3  # 921600 字节


def convert(src, dst, mode="fit", swap=False, width=W, height=H):
    img = Image.open(src)
    # 转成 RGB（去掉 alpha / 灰度等），并存为不带缩略信息的副本
    img = img.convert("RGB")

    target = (width, height)

    if mode == "stretch":
        # 直接拉伸
        canvas = img.resize(target, Image.LANCZOS)
    elif mode == "crop":
        # 等比缩放后居中裁剪，填满画布
        ratio = max(width / img.width, height / img.height)
        new_size = (round(img.width * ratio), round(img.height * ratio))
        img = img.resize(new_size, Image.LANCZOS)
        left = (img.width - width) // 2
        top = (img.height - height) // 2
        canvas = img.crop((left, top, left + width, top + height))
    else:  # fit（默认）
        # 等比缩放后居中放入黑色画布
        img.thumbnail(target, Image.LANCZOS)
        canvas = Image.new("RGB", target, (0, 0, 0))
        canvas.paste(img, ((width - img.width) // 2, (height - img.height) // 2))

    # canvas 已是 (RGB) 模式、大小与画布一致
    if canvas.size != target:
        canvas = canvas.resize(target, Image.LANCZOS)

    data = bytearray(canvas.tobytes())  # 顺序为逐像素 R,G,B

    if swap:
        # 交换每像素的 R 与 B（用于容错 BGR 顺序）
        for i in range(0, len(data), 3):
            data[i], data[i + 2] = data[i + 2], data[i]

    if len(data) != RAW_SIZE:
        sys.exit(
            f"生成数据大小为 {len(data)} 字节，期望 {RAW_SIZE} 字节，与案例不匹配！"
        )

    with open(dst, "wb") as f:
        f.write(data)

    if swap:
        mode_desc = f"{mode} + R/B交换"
    else:
        mode_desc = mode
    print(f"OK  读取: {src}")
    print(f"    输出: {dst}  ({width}x{height} RGB888, {len(data)} 字节, 模式: {mode_desc})")
    print(f"    用串口工具以 921600 波特率把 {src}{os.linesep}    这个文件发给 FPGA 的 uart_rx（收满后 FPGA 会回传这 {len(data)} 字节校验，然后进入 HDMI 显示）。")


def main():
    p = argparse.ArgumentParser(description="图片 -> 640x480 RGB888 裸数据（921600 字节）")
    p.add_argument("input", help="输入图片路径（jpg/png/bmp...）")
    p.add_argument("-o", "--output", default=None, help="输出文件路径（默认：输入文件名+.rgb）")
    p.add_argument("--mode", default="fit", choices=["fit", "crop", "stretch"],
                   help="缩放方式（默认 fit）")
    p.add_argument("--swap", action="store_true", help="交换 R/B（红蓝颠倒时使用）")
    p.add_argument("--size", default=f"{W}x{H}", help="输出分辨率（默认 640x480）")
    args = p.parse_args()

    try:
        width, height = (int(x) for x in args.size.lower().split("x"))
    except ValueError:
        sys.exit("--size 格式应为 宽x高，例如 640x480")

    if width * height * 3 != RAW_SIZE:
        sys.exit(f"分辨率 {width}x{height} 会产生 {width*height*3} 字节，"
                 f"与案例的 640x480=921600 字节不符！")

    if not os.path.exists(args.input):
        sys.exit(f"找不到输入文件: {args.input}")

    dst = args.output or (args.input.rsplit(".", 1)[0] + ".rgb")
    convert(args.input, dst, args.mode, args.swap, width, height)


if __name__ == "__main__":
    main()