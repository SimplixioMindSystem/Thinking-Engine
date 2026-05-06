#!/usr/bin/env python3
"""
SimpliXio App Store Marketing Screenshot Generator
─────────────────────────────────────────────────
Creates professional marketing screenshots with:
- Device frames (iPhone/iPad/Mac)
- Marketing headlines
- Branded gradient backgrounds
- Professional typography
"""

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ─────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────

ROOT = Path(__file__).parent.parent
ASSETS_DIR = ROOT / "CortexOSApp" / "store_assets"
RAW_DIR = ROOT / "CortexOSApp" / "screenshot_results"
OUTPUT_DIR = ASSETS_DIR / "marketing"
ALLOW_SCREENSHOT_FALLBACK = os.getenv("ALLOW_SCREENSHOT_FALLBACK", "0").strip().lower() in {"1", "true", "yes"}
REQUESTED_DEVICES = {
    item.strip()
    for item in os.getenv("STORE_ASSET_DEVICES", "").split(",")
    if item.strip()
}

# SimpliXio Brand Colors (vibrant, electric aesthetic)
BRAND_GRADIENT_START = (15, 23, 42)  # Deep navy
BRAND_GRADIENT_MID = (88, 28, 135)  # Vivid purple
BRAND_GRADIENT_END = (157, 23, 77)  # Hot magenta
BRAND_ACCENT_CYAN = (6, 182, 212)  # Electric cyan
BRAND_ACCENT_VIOLET = (139, 92, 246)  # Bright violet
BRAND_ACCENT_PINK = (236, 72, 153)  # Hot pink
BRAND_ACCENT_BLUE = (59, 130, 246)  # Electric blue
BRAND_TEXT_PRIMARY = (255, 255, 255)  # White
BRAND_TEXT_SECONDARY = (255, 255, 255, 200)  # White with alpha

# Marketing copy for each screen (conversion-first, concrete output language).
IPHONE_MARKETING = {
    "01_focus": {
        "headline": "Turn noise into\n3 priorities.",
        "subheadline": "See what matters now before opening another list.",
    },
    "02_decide": {
        "headline": "Know why\nit matters.",
        "subheadline": "Each priority explains the reason before the action.",
    },
    "03_capture": {
        "headline": "Take the\nnext action.",
        "subheadline": "One clear move replaces scattered open loops.",
    },
    "04_settings": {
        "headline": "Private by default.\nHuman in control.",
        "subheadline": "No autopublish. Approval required for private outreach.",
    },
}

MAC_MARKETING = [
    (
        "01_focus",
        {"headline": "Turn noise into 3 priorities", "subheadline": "See what matters now, why, and one next action."},
    ),
    (
        "02_insights",
        {"headline": "Know why it matters", "subheadline": "Weekly Review shows what repeated and what to do next."},
    ),
    (
        "03_queues",
        {
            "headline": "Review only what matters",
            "subheadline": "Decision Replay shows what was kept, ignored, and chosen.",
        },
    ),
    (
        "04_memory",
        {
            "headline": "Understand the why",
            "subheadline": "Decision Replay shows what was reviewed, kept, and ignored.",
        },
    ),
    (
        "05_decisions",
        {"headline": "Act with confidence", "subheadline": "Feedback improves future prioritization over time."},
    ),
    (
        "06_settings",
        {
            "headline": "Private by default",
            "subheadline": "Human stays in control. No autopublish for sensitive content.",
        },
    ),
]

# App Store screenshot dimensions
DIMENSIONS = {
    "iPhone_6.9": (1320, 2868),  # iPhone 16 Pro Max
    "iPhone_6.7": (1290, 2796),  # iPhone 14 Pro Max
    "iPhone_6.5": (1242, 2688),  # iPhone 11 Pro Max
    "iPhone_5.5": (1242, 2208),  # iPhone 8 Plus
    "iPad_13": (2064, 2752),  # iPad Pro 13"
    "iPad_12.9": (2048, 2732),  # iPad Pro 12.9"
    "Mac": (2880, 1800),  # macOS
}


def create_gradient(size, start_color, end_color, direction="vertical"):
    """Create a gradient image."""
    width, height = size
    gradient = Image.new("RGB", size)
    draw = ImageDraw.Draw(gradient)

    if direction == "vertical":
        for y in range(height):
            ratio = y / height
            r = int(start_color[0] * (1 - ratio) + end_color[0] * ratio)
            g = int(start_color[1] * (1 - ratio) + end_color[1] * ratio)
            b = int(start_color[2] * (1 - ratio) + end_color[2] * ratio)
            draw.line([(0, y), (width, y)], fill=(r, g, b))
    else:
        for x in range(width):
            ratio = x / width
            r = int(start_color[0] * (1 - ratio) + end_color[0] * ratio)
            g = int(start_color[1] * (1 - ratio) + end_color[1] * ratio)
            b = int(start_color[2] * (1 - ratio) + end_color[2] * ratio)
            draw.line([(x, 0), (x, height)], fill=(r, g, b))

    return gradient


def create_vibrant_background(size, variant=0):
    """Create a super vibrant multi-color gradient background with glowing orbs."""
    import math

    width, height = size

    # Create base with rich 3-stop gradient
    bg = Image.new("RGB", size)

    for y in range(height):
        ratio = y / height
        # 3-stop gradient: navy -> purple -> magenta
        if ratio < 0.5:
            t = ratio * 2
            r = int(BRAND_GRADIENT_START[0] * (1 - t) + BRAND_GRADIENT_MID[0] * t)
            g = int(BRAND_GRADIENT_START[1] * (1 - t) + BRAND_GRADIENT_MID[1] * t)
            b = int(BRAND_GRADIENT_START[2] * (1 - t) + BRAND_GRADIENT_MID[2] * t)
        else:
            t = (ratio - 0.5) * 2
            r = int(BRAND_GRADIENT_MID[0] * (1 - t) + BRAND_GRADIENT_END[0] * t)
            g = int(BRAND_GRADIENT_MID[1] * (1 - t) + BRAND_GRADIENT_END[1] * t)
            b = int(BRAND_GRADIENT_MID[2] * (1 - t) + BRAND_GRADIENT_END[2] * t)

        for x in range(width):
            # Add slight horizontal variation
            x_ratio = x / width
            shift = int(10 * math.sin(x_ratio * math.pi))
            bg.putpixel((x, y), (min(255, r + shift), g, min(255, b + shift)))

    bg = bg.convert("RGBA")

    # Add glowing accent orbs based on variant
    orb_configs = [
        # Variant 0: Cyan top-right, pink bottom-left
        [(0.75, 0.15, BRAND_ACCENT_CYAN, 0.25), (0.2, 0.85, BRAND_ACCENT_PINK, 0.3)],
        # Variant 1: Violet center-right, blue bottom
        [(0.8, 0.4, BRAND_ACCENT_VIOLET, 0.28), (0.3, 0.9, BRAND_ACCENT_BLUE, 0.25)],
        # Variant 2: Blue top-left, pink center-right
        [(0.25, 0.2, BRAND_ACCENT_BLUE, 0.22), (0.7, 0.5, BRAND_ACCENT_PINK, 0.28)],
        # Variant 3: Cyan center, violet bottom-right
        [(0.5, 0.35, BRAND_ACCENT_CYAN, 0.3), (0.8, 0.75, BRAND_ACCENT_VIOLET, 0.25)],
    ]

    orbs = orb_configs[variant % len(orb_configs)]

    for ox_ratio, oy_ratio, color, size_ratio in orbs:
        orb_x = int(width * ox_ratio)
        orb_y = int(height * oy_ratio)
        orb_radius = int(max(width, height) * size_ratio)

        # Create orb with gaussian-like falloff
        orb = Image.new("RGBA", size, (0, 0, 0, 0))
        for dy in range(-orb_radius, orb_radius + 1):
            for dx in range(-orb_radius, orb_radius + 1):
                px, py = orb_x + dx, orb_y + dy
                if 0 <= px < width and 0 <= py < height:
                    dist = math.sqrt(dx * dx + dy * dy)
                    if dist < orb_radius:
                        # Gaussian falloff for soft glow
                        intensity = math.exp(-3 * (dist / orb_radius) ** 2)
                        alpha = int(120 * intensity)
                        orb.putpixel((px, py), (*color, alpha))

        # Blur the orb for softer glow
        orb = orb.filter(ImageFilter.GaussianBlur(orb_radius // 4))
        bg = Image.alpha_composite(bg, orb)

    return bg


def add_device_frame(screenshot, device_type="iphone", corner_radius=40):
    """Add a device frame effect to the screenshot."""
    # Create rounded corners mask
    size = screenshot.size
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size[0], size[1]], radius=corner_radius, fill=255)

    # Apply mask
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.paste(screenshot, (0, 0))
    output.putalpha(mask)

    return output


def add_shadow(image, offset=(20, 20), blur_radius=40, shadow_color=(0, 0, 0, 100)):
    """Add a drop shadow to an image."""
    # Create shadow
    shadow_size = (image.size[0] + blur_radius * 2, image.size[1] + blur_radius * 2)
    shadow = Image.new("RGBA", shadow_size, (0, 0, 0, 0))

    # Get alpha channel from original image
    alpha = image.split()[3] if image.mode == "RGBA" else Image.new("L", image.size, 255)

    # Create shadow layer
    shadow_layer = Image.new("RGBA", image.size, shadow_color)
    shadow_layer.putalpha(alpha)

    # Paste shadow
    shadow.paste(shadow_layer, (blur_radius + offset[0], blur_radius + offset[1]))

    # Blur shadow
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius // 2))

    # Composite original on top
    final_size = (shadow_size[0] + abs(offset[0]), shadow_size[1] + abs(offset[1]))
    final = Image.new("RGBA", final_size, (0, 0, 0, 0))
    final.paste(shadow, (0, 0), shadow)
    final.paste(image, (blur_radius, blur_radius), image if image.mode == "RGBA" else None)

    return final


def get_font(size, bold=False, style="headline"):
    """Get an appealing system font."""
    # Elegant fonts for headlines vs body
    if style == "headline":
        font_paths = [
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",  # Elegant, modern
            "/Library/Fonts/SF-Pro-Display-Bold.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    else:
        font_paths = [
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
            "/Library/Fonts/SF-Pro-Display-Regular.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]

    for path in font_paths:
        if os.path.exists(path):
            try:
                # For .ttc files, index 0 is usually regular, higher indices are bolder
                if path.endswith(".ttc"):
                    index = 10 if bold or style == "headline" else 0  # Avenir Next Bold
                    return ImageFont.truetype(path, size, index=index)
                return ImageFont.truetype(path, size)
            except Exception:  # noqa: S112
                continue

    return ImageFont.load_default()


def draw_text_with_glow(
    image,
    position,
    text,
    font,
    fill=(255, 255, 255),
    glow_color=(0, 0, 0),
    glow_radius=15,
    accent_glow=True,
):
    """Draw text with a strong glow effect and optional accent color for appeal."""
    from PIL import Image as PILImage

    x, y = int(position[0]), int(position[1])

    # Get text size
    temp_draw = ImageDraw.Draw(image)
    bbox = temp_draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Create a larger canvas for the glow
    padding = int(glow_radius * 3)
    glow_size = (int(text_width + padding * 2), int(text_height + padding * 2))

    # Create dark glow layer for contrast
    glow_layer = PILImage.new("RGBA", glow_size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)

    # Draw multiple copies of text for thick dark glow
    for ox in range(-4, 5):
        for oy in range(-4, 5):
            glow_draw.text((padding + ox, padding + oy), text, font=font, fill=(0, 0, 0, 180))

    # Blur the dark glow
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(glow_radius))
    image.paste(glow_layer, (x - padding, y - padding), glow_layer)

    # Add subtle accent color glow (cyan/violet) for appeal
    if accent_glow:
        accent_layer = PILImage.new("RGBA", glow_size, (0, 0, 0, 0))
        accent_draw = ImageDraw.Draw(accent_layer)
        # Subtle cyan accent
        for ox in range(-2, 3):
            for oy in range(-2, 3):
                accent_draw.text((padding + ox, padding + oy), text, font=font, fill=(100, 200, 255, 60))
        accent_layer = accent_layer.filter(ImageFilter.GaussianBlur(glow_radius // 2))
        image.paste(accent_layer, (x - padding, y - padding), accent_layer)

    # Draw crisp text on top with subtle warm white
    draw = ImageDraw.Draw(image)
    # Soft outline for crispness
    for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        draw.text((x + ox, y + oy), text, font=font, fill=(0, 0, 0, 80))
    # Main text - slightly warm white for appeal
    text_color = (255, 252, 250) if fill == (255, 255, 255) else fill[:3]
    draw.text((x, y), text, font=font, fill=text_color)


def draw_text_with_shadow(draw, position, text, font, fill=(255, 255, 255), shadow_color=(0, 0, 0, 180)):
    """Draw text with strong multi-layer shadow for readability."""
    x, y = position
    # Draw multiple shadow layers for a blur/glow effect
    shadow_offsets = [
        (8, 8, (0, 0, 0, 60)),  # Outer shadow
        (6, 6, (0, 0, 0, 80)),  # Middle shadow
        (4, 4, (0, 0, 0, 100)),  # Inner shadow
        (2, 2, (0, 0, 0, 140)),  # Close shadow
    ]
    for ox, oy, color in shadow_offsets:
        draw.text((x + ox, y + oy), text, font=font, fill=color)
    # Draw main text
    draw.text((x, y), text, font=font, fill=fill)


def create_iphone_screenshot(raw_path, marketing_info, output_size, variant=0):
    """Create a marketing screenshot for iPhone."""
    width, height = output_size

    # Create vibrant gradient background with glowing orbs
    bg = create_vibrant_background(output_size, variant=variant)

    # Load and process screenshot
    try:
        screenshot = Image.open(raw_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  Could not load {raw_path}: {e}")
        return bg

    # Calculate screenshot size (65% of height, maintaining aspect ratio)
    target_height = int(height * 0.58)
    aspect = screenshot.size[0] / screenshot.size[1]
    target_width = int(target_height * aspect)

    screenshot = screenshot.resize((target_width, target_height), Image.Resampling.LANCZOS)

    # Add rounded corners and shadow
    screenshot = add_device_frame(screenshot, corner_radius=int(target_width * 0.04))
    screenshot = add_shadow(screenshot, offset=(15, 25), blur_radius=50)

    # Position screenshot (centered, bottom third)
    ss_x = (width - screenshot.size[0]) // 2
    ss_y = height - screenshot.size[1] + 40

    # Add dark gradient overlay at top for text readability
    text_area_height = int(height * 0.35)
    overlay = Image.new("RGBA", (width, text_area_height), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    for y_pos in range(text_area_height):
        # Stronger gradient from dark (top) to transparent (bottom)
        alpha = int(120 * (1 - y_pos / text_area_height) ** 0.6)
        overlay_draw.line([(0, y_pos), (width, y_pos)], fill=(0, 0, 0, alpha))
    bg.paste(overlay, (0, 0), overlay)

    bg.paste(screenshot, (ss_x, ss_y), screenshot)

    # Add marketing text with glow effect
    # Headline
    headline_font_size = int(width * 0.09)  # Slightly larger
    headline_font = get_font(headline_font_size, bold=True, style="headline")

    headline = marketing_info.get("headline", "SimpliXio")

    # Calculate text position (centered, top area)
    lines = headline.split("\n")
    total_text_height = len(lines) * (headline_font_size * 1.2)
    text_y = int(height * 0.07)

    for i, line in enumerate(lines):
        # Get text bounding box for centering
        temp_draw = ImageDraw.Draw(bg)
        bbox = temp_draw.textbbox((0, 0), line, font=headline_font)
        text_width = bbox[2] - bbox[0]
        text_x = (width - text_width) // 2
        line_y = text_y + i * int(headline_font_size * 1.2)
        draw_text_with_glow(bg, (text_x, line_y), line, headline_font, glow_radius=18)

    # Subheadline with glow
    subheadline = marketing_info.get("subheadline", "")
    if subheadline:
        sub_font_size = int(width * 0.04)
        sub_font = get_font(sub_font_size, style="body")
        temp_draw = ImageDraw.Draw(bg)
        bbox = temp_draw.textbbox((0, 0), subheadline, font=sub_font)
        sub_width = bbox[2] - bbox[0]
        sub_x = (width - sub_width) // 2
        sub_y = text_y + total_text_height + int(height * 0.02)
        draw_text_with_glow(
            bg,
            (sub_x, sub_y),
            subheadline,
            sub_font,
            fill=(220, 230, 255),
            glow_radius=10,
            accent_glow=False,
        )

    return bg.convert("RGB")


def create_ipad_screenshot(raw_path, marketing_info, output_size, variant=0):
    """Create a marketing screenshot for iPad (similar layout to iPhone)."""
    return create_iphone_screenshot(raw_path, marketing_info, output_size, variant=variant)


def create_mac_screenshot(raw_path, marketing_info, output_size, variant=0):
    """Create a marketing screenshot for Mac (horizontal layout)."""
    width, height = output_size

    # Create vibrant gradient background with glowing orbs
    bg = create_vibrant_background(output_size, variant=variant)

    # Load and process screenshot
    try:
        screenshot = Image.open(raw_path).convert("RGBA")
    except Exception as e:
        print(f"  ⚠️  Could not load {raw_path}: {e}")
        return bg

    # Calculate screenshot size (70% of width, maintaining aspect ratio)
    target_width = int(width * 0.65)
    aspect = screenshot.size[1] / screenshot.size[0]
    target_height = int(target_width * aspect)

    # Cap height if needed
    if target_height > height * 0.75:
        target_height = int(height * 0.75)
        target_width = int(target_height / aspect)

    screenshot = screenshot.resize((target_width, target_height), Image.Resampling.LANCZOS)

    # Add rounded corners and shadow
    screenshot = add_device_frame(screenshot, corner_radius=int(target_width * 0.015))
    screenshot = add_shadow(screenshot, offset=(20, 30), blur_radius=60)

    # Position screenshot (right side, ensure it doesn't overlap text area)
    text_area_end = int(width * 0.38)  # Text area takes ~38% of width
    ss_x = max(text_area_end + 20, width - screenshot.size[0] - int(width * 0.02))
    ss_y = (height - screenshot.size[1]) // 2 + 20

    # Add dark gradient overlay on left side for text readability
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    gradient_width = text_area_end + 150
    for x_pos in range(gradient_width):
        # Stronger gradient from dark (left) to transparent (right)
        alpha = int(140 * (1 - x_pos / gradient_width) ** 0.6)
        overlay_draw.line([(x_pos, 0), (x_pos, height)], fill=(0, 0, 0, alpha))
    bg = Image.alpha_composite(bg, overlay)

    bg.paste(screenshot, (ss_x, ss_y), screenshot)

    # Add marketing text (left side) with glow for readability
    headline_font_size = int(height * 0.085)  # Slightly larger for impact
    headline_font = get_font(headline_font_size, bold=True, style="headline")

    headline = marketing_info.get("headline", "SimpliXio")

    # Text area is left 5% of width
    text_x = int(width * 0.05)
    text_y = (height - headline_font_size * 3) // 2 - 40

    lines = headline.split("\n")
    for i, line in enumerate(lines):
        line_y = text_y + i * int(headline_font_size * 1.2)
        draw_text_with_glow(bg, (text_x, line_y), line, headline_font, glow_radius=25)

    # Subheadline with glow
    subheadline = marketing_info.get("subheadline", "")
    if subheadline:
        sub_font_size = int(height * 0.038)
        sub_font = get_font(sub_font_size, style="body")
        sub_y = text_y + len(lines) * int(headline_font_size * 1.2) + 30
        draw_text_with_glow(
            bg,
            (text_x, sub_y),
            subheadline,
            sub_font,
            fill=(220, 230, 255),
            glow_radius=12,
            accent_glow=False,
        )

    return bg.convert("RGB")


def should_process_device(device):
    """Allow App Store asset generation for one device class without touching stale others."""
    return not REQUESTED_DEVICES or device in REQUESTED_DEVICES


def process_all_screenshots():
    """Process all screenshots and create marketing versions."""
    print("═" * 55)
    print(" SimpliXio — Marketing Screenshot Generator")
    print("═" * 55)
    if ALLOW_SCREENSHOT_FALLBACK:
        print("⚠️  Fallback enabled: missing raw captures may reuse older store assets.")
    else:
        print("✅ Strict mode: only raw captures are used.")

    # Create output directories and clear old PNGs to avoid stale listing assets.
    for device in DIMENSIONS:
        if not should_process_device(device):
            continue
        device_dir = OUTPUT_DIR / device
        device_dir.mkdir(parents=True, exist_ok=True)
        for stale_png in device_dir.glob("*.png"):
            stale_png.unlink()

    # Process iPhone screenshots
    print("\n📱 Processing iPhone screenshots...")
    for device in ["iPhone_6.9", "iPhone_6.7", "iPhone_6.5", "iPhone_5.5"]:
        if not should_process_device(device):
            continue
        print(f"\n  {device}:")
        output_size = DIMENSIONS[device]

        for idx, (screen_name, marketing) in enumerate(IPHONE_MARKETING.items()):
            # Always prefer raw captures to avoid recursively styling already-marketing assets.
            raw_path = RAW_DIR / "iphone_raw" / f"{screen_name}.png"
            if not raw_path.exists() and ALLOW_SCREENSHOT_FALLBACK:
                raw_path = ASSETS_DIR / device / f"{screen_name}.png"

            if raw_path.exists():
                print(f"    → {screen_name}")
                result = create_iphone_screenshot(raw_path, marketing, output_size, variant=idx)
                result.save(OUTPUT_DIR / device / f"{screen_name}.png", quality=95)
            else:
                print(f"    ⚠️  Missing: {screen_name}")

    # Process iPad screenshots
    print("\n📱 Processing iPad screenshots...")
    for device in ["iPad_13", "iPad_12.9"]:
        if not should_process_device(device):
            continue
        print(f"\n  {device}:")
        output_size = DIMENSIONS[device]

        for idx, (screen_name, marketing) in enumerate(IPHONE_MARKETING.items()):  # Same screens as iPhone
            raw_path = RAW_DIR / "ipad_raw" / f"{screen_name}.png"
            if not raw_path.exists() and ALLOW_SCREENSHOT_FALLBACK:
                raw_path = ASSETS_DIR / device / f"{screen_name}.png"

            if raw_path.exists():
                print(f"    → {screen_name}")
                result = create_ipad_screenshot(raw_path, marketing, output_size, variant=idx)
                result.save(OUTPUT_DIR / device / f"{screen_name}.png", quality=95)
            else:
                print(f"    ⚠️  Missing: {screen_name}")

    # Process Mac screenshots
    if should_process_device("Mac"):
        print("\n🖥️  Processing Mac screenshots...")
        output_size = DIMENSIONS["Mac"]

        for idx, (screen_name, marketing) in enumerate(MAC_MARKETING):
            raw_path = RAW_DIR / "mac_raw" / f"{screen_name}.png"
            if not raw_path.exists() and ALLOW_SCREENSHOT_FALLBACK:
                raw_path = ASSETS_DIR / "Mac" / f"{screen_name}.png"

            if raw_path.exists():
                print(f"    → {screen_name}")
                result = create_mac_screenshot(raw_path, marketing, output_size, variant=idx)
                result.save(OUTPUT_DIR / "Mac" / f"{screen_name}.png", quality=95)
            else:
                print(f"    ⚠️  Missing: {screen_name}")

    print("\n" + "═" * 55)
    print(" ✅ Marketing screenshots saved to:")
    print(f"    {OUTPUT_DIR}")
    print("═" * 55)

    # Summary
    print("\nGenerated screenshots:")
    for device in DIMENSIONS:
        if not should_process_device(device):
            continue
        device_dir = OUTPUT_DIR / device
        if device_dir.exists():
            count = len(list(device_dir.glob("*.png")))
            print(f"  {device}: {count} screenshots")


if __name__ == "__main__":
    process_all_screenshots()
