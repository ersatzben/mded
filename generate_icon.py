#!/usr/bin/env python3
"""Generate mded app icon at all required sizes."""

from PIL import Image, ImageDraw, ImageFont
import os

def draw_icon(size):
    """Draw mded icon: rounded rect with M and a hand-drawn down arrow."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = int(size * 0.08)
    radius = int(size * 0.18)

    # Background
    bg_color = (30, 35, 45)
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=radius, fill=bg_color,
    )
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=radius, outline=(60, 70, 90), width=max(1, size // 256),
    )

    # "M" - bold white
    font_size = int(size * 0.42)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFCompact-Bold.otf", font_size)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

    m_color = (240, 240, 245)
    m_bbox = draw.textbbox((0, 0), "M", font=font)
    m_w = m_bbox[2] - m_bbox[0]
    m_h = m_bbox[3] - m_bbox[1]
    m_x = (size - m_w) // 2
    m_y = int(size * 0.15)
    draw.text((m_x, m_y), "M", fill=m_color, font=font)

    # Draw down arrow manually (GitHub blue)
    arrow_color = (88, 166, 255)
    cx = size // 2
    arrow_top = m_y + m_h + int(size * 0.04)
    arrow_bottom = arrow_top + int(size * 0.18)
    shaft_w = int(size * 0.035)
    head_w = int(size * 0.09)
    head_h = int(size * 0.08)

    # Shaft
    draw.rectangle(
        [cx - shaft_w, arrow_top, cx + shaft_w, arrow_bottom - head_h],
        fill=arrow_color,
    )
    # Arrowhead triangle
    draw.polygon(
        [(cx - head_w, arrow_bottom - head_h),
         (cx + head_w, arrow_bottom - head_h),
         (cx, arrow_bottom)],
        fill=arrow_color,
    )

    return img


sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

out_dir = "mded/Resources/Assets.xcassets/AppIcon.appiconset"
master = draw_icon(1024)

for filename, px in sizes.items():
    resized = master.resize((px, px), Image.LANCZOS)
    resized.save(os.path.join(out_dir, filename))
    print(f"  {filename} ({px}x{px})")

print("Done!")
