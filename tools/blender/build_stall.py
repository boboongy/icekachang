"""Builds the hawker stall scene and its pixel textures, exports assets/models/stall.glb.

Run headless:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/build_stall.py

Look and layout follow plan/references/05-real-stall-front.png (owner: ref 05 is THE reference).
Ref 03 only sets the rendering style: chunky low-poly, low-res textures, flat saturated colours.

Coordinates here are Blender's: X right, Y into the stall (away from the customer), Z up.
The stall front is at y = 0, customers stand at negative y. glTF export turns this into Godot's
(x, z, -y), so in Godot the stall faces +Z.

Materials (Godot replaces them by name, see scripts/retro_materials.gd):
  atlas    lit, uses assets/textures/atlas.png (colour swatches + painted regions)
  glow     unshaded, same atlas (lightbox, tubes, fridge fronts)
  floor    lit, assets/textures/floor.png, repeats every FLOOR_TILE metres
  walltile lit, assets/textures/walltile.png, repeats every WALL_TILE metres
  glass    see-through
"""
import bpy
import json
import math
import os
import random
import sys

import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
OUT_GLB = os.path.join(ROOT, "assets", "models", "stall.glb")
MENU = json.load(open(os.path.join(ROOT, "data", "menu.json")))["items"]
INGREDIENTS = json.load(open(os.path.join(ROOT, "data", "recipes.json")))["ingredients"]
TOPPINGS = sorted((k for k, v in INGREDIENTS.items() if v["kind"] == "topping"), key=lambda k: INGREDIENTS[k]["slot"])
SAUCES = sorted((k for k, v in INGREDIENTS.items() if v["kind"] == "sauce"), key=lambda k: INGREDIENTS[k]["slot"])

FLOOR_TILE = 1.2   # metres covered by floor.png
WALL_TILE = 0.6    # metres covered by walltile.png
REPEAT_MATS = {"floor": FLOOR_TILE, "walltile": WALL_TILE}

rng = random.Random(7)


# ---------------------------------------------------------------------------
# Pixel painting (numpy, top-left origin, RGBA floats 0..1)
# ---------------------------------------------------------------------------

def C(r, g, b, a=255):
    return np.array([r / 255, g / 255, b / 255, a / 255], dtype=np.float32)


class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0)):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), dtype=np.float32)
        self.a[:, :] = C(*fill)

    def rect(self, x, y, w, h, col):
        x0, y0 = max(int(x), 0), max(int(y), 0)
        x1, y1 = min(int(x + w), self.w), min(int(y + h), self.h)
        if x1 > x0 and y1 > y0:
            self.a[y0:y1, x0:x1] = col

    def px(self, x, y, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[int(y), int(x)] = col

    def outline(self, x, y, w, h, col):
        self.rect(x, y, w, 1, col)
        self.rect(x, y + h - 1, w, 1, col)
        self.rect(x, y, 1, h, col)
        self.rect(x + w - 1, y, 1, h, col)

    def ellipse(self, cx, cy, rx, ry, col, top_only=False):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            if top_only and y > cy:
                break
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / max(rx, 0.01)) ** 2 + ((y - cy) / max(ry, 0.01)) ** 2 <= 1.0:
                    self.px(x, y, col)

    def noise(self, x, y, w, h, amount, seed=0):
        """Slight per-pixel brightness jitter: the low-res 'photo texture' feel of ref 03."""
        r = np.random.default_rng(seed)
        region = self.a[y:y + h, x:x + w, :3]
        region *= 1.0 + (r.random(region.shape[:2])[..., None] - 0.5) * amount
        np.clip(region, 0, 1, out=region)

    def text(self, x, y, s, col, font="5x7", scale=1, shadow=None):
        glyphs = FONT5 if font == "5x7" else FONT3
        cx = x
        for ch in s:
            g = glyphs.get(ch)
            if g is None:
                cx += (3 if font == "5x7" else 2) * scale
                continue
            for gy, row in enumerate(g):
                for gx, c in enumerate(row):
                    if c == "#":
                        if shadow is not None:
                            self.rect(cx + gx * scale + 1, y + gy * scale + 1, scale, scale, shadow)
                        self.rect(cx + gx * scale, y + gy * scale, scale, scale, col)
            cx += (len(g[0]) + 1) * scale
        return cx - x

    def text_width(self, s, font="5x7", scale=1):
        glyphs = FONT5 if font == "5x7" else FONT3
        w = 0
        for ch in s:
            g = glyphs.get(ch)
            w += ((len(g[0]) + 1) if g else (3 if font == "5x7" else 2)) * scale
        return w - scale

    def text_c(self, cx, y, s, col, font="5x7", scale=1, shadow=None):
        self.text(cx - self.text_width(s, font, scale) // 2, y, s, col, font, scale, shadow)

    def save(self, path):
        img = bpy.data.images.new(os.path.basename(path), self.w, self.h, alpha=True)
        img.pixels.foreach_set(np.flipud(self.a).ravel())
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()


FONT5 = {
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "I": ["###", " # ", " # ", " # ", " # ", " # ", "###"],
    "J": ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
    "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
    "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
    "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
    "&": [" ##  ", "#  # ", "# #  ", " #   ", "# # #", "#  # ", " ## #"],
    "-": ["   ", "   ", "   ", "###", "   ", "   ", "   "],
    "!": ["#", "#", "#", "#", "#", " ", "#"],
    ".": [" ", " ", " ", " ", " ", " ", "#"],
    "'": ["#", "#", " ", " ", " ", " ", " "],
    "$": [" ### ", "# #  ", " ### ", "  # #", " ### ", "  #  ", "     "],
}

FONT3 = {
    "0": ["###", "# #", "# #", "# #", "###"],
    "1": [" # ", "## ", " # ", " # ", "###"],
    "2": ["###", "  #", "###", "#  ", "###"],
    "3": ["###", "  #", "###", "  #", "###"],
    "4": ["# #", "# #", "###", "  #", "  #"],
    "5": ["###", "#  ", "###", "  #", "###"],
    "6": ["###", "#  ", "###", "# #", "###"],
    "7": ["###", "  #", "  #", "  #", "  #"],
    "8": ["###", "# #", "###", "# #", "###"],
    "9": ["###", "# #", "###", "  #", "###"],
    "$": [" ##", "## ", " # ", " ##", "## "],
    ".": [" ", " ", " ", " ", "#"],
    "-": ["   ", "   ", "###", "   ", "   "],
    "O": ["###", "# #", "# #", "# #", "###"],
    "P": ["###", "# #", "###", "#  ", "#  "],
    "E": ["###", "#  ", "## ", "#  ", "###"],
    "N": ["# #", "###", "###", "# #", "# #"],
}


# ---------------------------------------------------------------------------
# Atlas: colour swatches in the top 32 rows, painted regions below
# ---------------------------------------------------------------------------

ATLAS_W = ATLAS_H = 256
atlas = Canvas(ATLAS_W, ATLAS_H, (255, 0, 255))

PALETTE = {
    # stall structure
    "white": (236, 236, 230), "offwhite": (214, 212, 204), "steel": (178, 184, 190),
    "steel_dark": (120, 126, 134), "black": (28, 28, 32), "darkgrey": (58, 60, 66),
    "grey": (130, 132, 136), "ceiling": (226, 228, 226), "sign_pink": (226, 64, 112),
    "sign_red": (196, 40, 52), "tube": (255, 255, 250), "lightbox_back": (40, 44, 52),
    "cabinet": (46, 44, 48), "table_top": (232, 232, 222), "basin_yellow": (240, 200, 40),
    "pillar": (238, 236, 228), "hall_wall": (222, 220, 210), "beam": (200, 200, 196),
    "kerb": (150, 152, 150), "paper": (246, 244, 236), "glass_frame": (190, 196, 200),
    # food colours
    "ice": (238, 244, 250), "rose": (232, 70, 110), "green_syrup": (90, 196, 90),
    "red_bean": (110, 30, 36), "corn": (250, 210, 60), "attap": (240, 240, 220),
    "grass_jelly": (40, 34, 36), "jelly_red": (230, 50, 60), "jelly_green": (60, 200, 100),
    "mango": (255, 170, 30), "pandan": (70, 190, 80), "gula": (110, 60, 30),
    "coconut": (250, 248, 240), "soup_yellow": (232, 210, 120), "durian": (238, 214, 110),
    "milk": (255, 252, 236), "pot_inner": (60, 52, 40),
    # props
    "bowl_glass": (196, 226, 230), "bowl_white": (240, 240, 236), "bowl_rim": (60, 110, 190),
    "shaver_cream": (212, 198, 168), "shaver_blue": (120, 180, 220), "bottle_red": (210, 40, 60),
    "bottle_green": (60, 160, 70), "bottle_brown": (120, 70, 30), "can_white": (230, 230, 220),
    "tub_steel": (200, 204, 208), "burner": (40, 40, 44), "plastic_blue": (40, 110, 200),
    "plastic_red": (210, 50, 50), "stool_red": (200, 40, 40), "fan_white": (232, 232, 226),
    "shutter": (170, 174, 176), "orange": (250, 140, 30), "lime": (150, 210, 60),
    "wood": (150, 100, 60), "clock_red": (200, 40, 40), "water": (180, 210, 230),
    "glass_inner": (150, 196, 206), "glass_rim": (236, 252, 255), "glass_foot": (120, 186, 196), "ice_block": (176, 208, 230), "milk_block": (252, 238, 206),
    "bottle_orange": (246, 146, 24), "tray_pink": (236, 96, 140), "bin_red": (200, 46, 52),
    "you_tiao": (192, 116, 40), "you_tiao_lt": (226, 164, 72),
    # uncle
    "skin": (214, 160, 118), "skin_dark": (180, 128, 90), "singlet": (246, 246, 242),
    "shorts": (70, 76, 90), "hair": (150, 150, 150), "slipper": (40, 90, 170),
    "towel": (244, 244, 236), "specs": (20, 20, 22),
    # neighbours
    "nb_yellow": (250, 200, 40), "nb_orange": (240, 110, 30), "nb_green": (60, 160, 90),
    "nb_blue": (60, 120, 200),
    # customers (M4)
    "c_skin_lt": (232, 184, 146), "c_skin_md": (206, 150, 106), "c_skin_dk": (164, 112, 76),
    "c_hair_black": (32, 28, 30), "c_hair_brown": (84, 52, 34), "c_hair_grey": (168, 168, 170),
    "c_hair_white": (236, 236, 232), "c_shirt": (242, 244, 248), "c_navy": (44, 54, 96),
    "c_black": (40, 40, 46), "c_shoe_black": (26, 24, 26), "c_shoe_white": (236, 236, 236),
    "c_floral": (214, 72, 96), "c_blazer": (84, 88, 104), "c_skirt": (66, 68, 82),
    "c_polo": (56, 150, 108), "c_khaki": (196, 176, 134), "c_lilac": (192, 160, 232),
    "c_denim": (82, 112, 172), "c_hivis": (255, 132, 20), "c_work_grey": (108, 112, 118),
    "c_hardhat": (250, 208, 30), "c_samfu": (118, 168, 222), "c_backpack": (220, 62, 62),
    "c_bag": (132, 72, 40), "c_sandal": (122, 82, 52), "c_boot": (72, 52, 34),
}
SWATCH = {}
for i, (name, rgb) in enumerate(PALETTE.items()):
    cx, cy = (i % 32) * 8, (i // 32) * 8
    atlas.rect(cx, cy, 8, 8, C(*rgb))
    SWATCH[name] = ((cx + 4) / ATLAS_W, 1.0 - (cy + 4) / ATLAS_H)
assert len(PALETTE) <= 128

REGIONS = {}  # name -> (x, y, w, h) in atlas pixels


def region(name, x, y, w, h):
    REGIONS[name] = (x, y, w, h)
    return x, y, w, h


def paint_signboard():
    # Ref 05: hot-pink signboard across the top, white title, food photos at both ends.
    x, y, w, h = region("sign_ours", 0, 32, 256, 32)
    atlas.rect(x, y, w, h, C(232, 70, 118))
    atlas.rect(x, y + h - 4, w, 4, C(200, 40, 90))
    atlas.noise(x, y, w, h, 0.08, 1)
    atlas.rect(x, y, w, 1, C(255, 220, 90))
    atlas.rect(x, y + h - 1, w, 1, C(255, 220, 90))
    atlas.text_c(x + w // 2, y + 4, "ICE KACHANG", C(255, 255, 255), scale=2, shadow=C(120, 20, 60))
    atlas.text_c(x + w // 2, y + 21, "COLD & HOT DESSERTS", C(255, 230, 110), shadow=C(120, 20, 60))
    # the four v1 desserts at each end, drawn straight on the pink like the lightbox menu art
    # (owner: no plates, no tiles, just the dessert)
    for cx, item in ((x + 15, "ice_kachang"), (x + 42, "mango_milk_ice"), (x + w - 42, "chendol"), (x + w - 15, "tau_suan")):
        draw_dessert(atlas, cx, y + 28, item)


def draw_dessert(cv, cx, by, item_id):
    """Little dessert 'photo' for menu tiles. cx = centre x, by = bowl bottom y."""
    soup = item_id in ("tau_suan", "bobo_chacha", "pulut_hitam")
    if soup:
        # wide white bowl with blue rim, soup surface seen from above
        for i in range(7):
            half = 11 - i // 2
            cv.rect(cx - half, by - 7 + i, half * 2, 1, C(240, 240, 236))
        cv.rect(cx - 11, by - 8, 22, 1, C(60, 110, 190))
        surf = {"tau_suan": C(232, 206, 110), "bobo_chacha": C(244, 236, 214),
                "pulut_hitam": C(60, 24, 50)}[item_id]
        cv.ellipse(cx, by - 9, 10, 3, surf)
        if item_id == "tau_suan":
            cv.rect(cx + 3, by - 15, 9, 3, C(200, 140, 60))   # you tiao on the side
            cv.rect(cx + 4, by - 14, 7, 1, C(230, 180, 90))
        elif item_id == "bobo_chacha":
            for dx, dy, c in ((-5, 0, C(150, 80, 170)), (2, -1, C(250, 150, 50)), (5, 1, C(150, 80, 170)), (-1, 1, C(255, 255, 255))):
                cv.rect(cx + dx, by - 9 + dy, 2, 2, c)
        else:
            cv.rect(cx - 4, by - 10, 8, 1, C(250, 248, 240))
            cv.rect(cx - 2, by - 9, 5, 1, C(250, 248, 240))
        return
    # stemmed glass bowl
    cv.rect(cx - 3, by - 2, 6, 2, C(170, 210, 220))
    for i in range(6):
        half = 9 - i // 2
        cv.rect(cx - half, by - 8 + i, half * 2, 1, C(196, 226, 230))
    cv.rect(cx - 10, by - 9, 20, 1, C(230, 245, 250))
    # shaved ice mound
    top = by - 9
    if item_id.startswith("ice_kachang"):
        bands = [C(232, 70, 110), C(90, 196, 90), C(250, 210, 60), C(232, 70, 110)]
        for yy in range(13):
            half = int(9 * math.sqrt(max(0.0, 1 - (yy / 13) ** 2)))
            for xx in range(-half, half + 1):
                band = bands[min(3, max(0, (xx + 9) * 4 // 19))]
                cv.px(cx + xx, top - yy, band)
        cv.rect(cx - 3, top - 12, 6, 2, C(255, 252, 236))          # evaporated milk
        cv.px(cx - 5, top - 3, C(110, 30, 36)); cv.px(cx + 4, top - 2, C(250, 210, 60))
        if item_id.endswith("mango"):
            for dx, dy in ((-3, -13), (1, -14), (3, -12)):
                cv.rect(cx + dx, top + dy, 2, 2, C(255, 160, 20))
        elif item_id.endswith("durian"):
            cv.ellipse(cx, top - 13, 4, 2, C(238, 214, 110))
    elif item_id == "mango_milk_ice":
        cv.ellipse(cx, top, 9, 12, C(255, 250, 236), top_only=True)
        for dx, dy in ((-6, -3), (-2, -6), (3, -4), (5, -1), (0, -10), (-4, -8)):
            cv.rect(cx + dx, top + dy, 2, 2, C(255, 160, 20))
        cv.rect(cx - 4, top - 11, 8, 1, C(255, 190, 60))
    else:  # chendol
        cv.ellipse(cx, top, 9, 11, C(250, 248, 240), top_only=True)
        for yy in range(1, 10, 2):
            cv.rect(cx - 7 + (yy % 3), top - yy, 14 - 2 * (yy % 3), 1, C(140, 80, 40))
        for dx, dy in ((-5, -2), (-1, -5), (3, -3), (5, -6), (0, -8)):
            cv.rect(cx + dx, top + dy, 3, 1, C(70, 190, 80))
        if item_id.endswith("durian"):
            cv.ellipse(cx, top - 11, 4, 2, C(238, 214, 110))


def paint_menu_lightbox():
    # Ref 01 + 05: backlit menu strip of numbered photo tiles with prices.
    x, y, w, h = region("menu_ours", 0, 64, 256, 48)
    atlas.rect(x, y, w, h, C(30, 70, 170))
    atlas.rect(x, y, w, 2, C(90, 140, 230))
    for i, item in enumerate(MENU):
        tx = x + 2 + i * 28
        ty = y + 3
        atlas.rect(tx, ty, 27, 43, C(252, 250, 244))
        atlas.rect(tx, ty + 30, 27, 13, C(255, 236, 120))
        draw_dessert(atlas, tx + 14, ty + 29, item["id"])
        atlas.rect(tx, ty, 7, 7, C(220, 40, 50))
        atlas.text(tx + 2, ty + 1, str(item["no"]), C(255, 255, 255), font="3x5")
        price = "$%d.%02d" % (item["price"] // 100, item["price"] % 100)
        atlas.text_c(tx + 14, ty + 34, price, C(200, 30, 40), font="3x5")
    atlas.noise(x, y, w, h, 0.05, 2)


def paint_neighbours():
    x, y, w, h = region("sign_left", 0, 112, 128, 16)
    atlas.rect(x, y, w, h, C(250, 200, 40))
    atlas.rect(x, y + h - 2, w, 2, C(220, 150, 20))
    atlas.text_c(x + w // 2, y + 4, "FRESH JUICE", C(200, 40, 40))
    for cx in (x + 8, x + w - 9):
        atlas.ellipse(cx, y + 8, 5, 5, C(250, 140, 30))
        atlas.px(cx, y + 3, C(60, 160, 70))

    x, y, w, h = region("sign_right", 128, 112, 128, 16)
    atlas.rect(x, y, w, h, C(240, 110, 30))
    atlas.rect(x, y + h - 2, w, 2, C(200, 70, 20))
    atlas.text_c(x + w // 2, y + 4, "FISHBALL NOODLE", C(255, 255, 255), shadow=C(140, 40, 10))

    # neighbour menus: drinks cups / noodle bowls
    x, y, w, h = region("menu_left", 0, 128, 128, 24)
    atlas.rect(x, y, w, h, C(250, 245, 230))
    cols = [C(250, 140, 30), C(150, 210, 60), C(240, 80, 90), C(250, 220, 80), C(120, 60, 30)]
    for i in range(8):
        tx = x + 3 + i * 15
        atlas.rect(tx + 3, y + 3, 8, 13, C(220, 236, 240))
        atlas.rect(tx + 4, y + 6, 6, 10, cols[i % 5])
        atlas.text(tx + 2, y + 18, "$%d" % (2 + i % 3), C(200, 40, 40), font="3x5")
    x, y, w, h = region("menu_right", 128, 128, 128, 24)
    atlas.rect(x, y, w, h, C(40, 40, 46))
    for i in range(6):
        tx = x + 3 + i * 20
        atlas.rect(tx, y + 2, 18, 20, C(250, 248, 240))
        atlas.ellipse(tx + 9, y + 9, 7, 3, C(240, 200, 120))
        atlas.rect(tx + 4, y + 8, 3, 3, C(250, 250, 250))
        atlas.rect(tx + 10, y + 7, 3, 3, C(250, 250, 250))
        atlas.rect(tx + 3, y + 10, 12, 1, C(80, 140, 60))
        atlas.text(tx + 3, y + 15, "$4", C(200, 40, 40), font="3x5")


def paint_props():
    # Fruit / greens poster on the display counter base (ref 05).
    x, y, w, h = region("poster_fruit", 0, 152, 64, 28)
    atlas.rect(x, y, w, h, C(70, 150, 70))
    for i in range(70):
        px_, py_ = x + rng.randrange(w), y + rng.randrange(h)
        atlas.ellipse(px_, py_, 2, 2, C(40 + rng.randrange(60), 120 + rng.randrange(90), 40 + rng.randrange(40)))
    for cx, cy, col in ((10, 20, C(240, 60, 50)), (22, 8, C(250, 160, 30)), (40, 18, C(250, 220, 60)),
                        (54, 9, C(240, 60, 50)), (30, 22, C(200, 230, 120)), (48, 24, C(250, 160, 30))):
        atlas.ellipse(x + cx, y + cy, 4, 4, col)
        atlas.px(x + cx - 1, y + cy - 2, C(255, 255, 255))
    atlas.rect(x + 36, y + 2, 26, 9, C(255, 255, 255))
    atlas.text_c(x + 49, y + 4, "100", C(40, 120, 50), font="3x5")
    atlas.outline(x, y, w, h, C(230, 230, 220))

    # Paper menus pasted along the top of the display case.
    x, y, w, h = region("paper", 64, 152, 48, 16)
    atlas.rect(x, y, w, h, C(246, 244, 236))
    for i in range(3):
        px_ = x + 1 + i * 16
        atlas.rect(px_, y + 1, 14, 14, [C(252, 250, 240), C(255, 236, 200), C(236, 246, 255)][i])
        atlas.rect(px_ + 1, y + 2, 12, 5, [C(232, 70, 110), C(250, 160, 30), C(90, 160, 220)][i])
        for ly in range(9, 14, 2):
            atlas.rect(px_ + 2, y + ly, 10 - (ly % 3), 1, C(80, 80, 90))

    # "OPEN" sign (red letters on white, like the stand in ref 05). Chunky 3x5 letters at about
    # one texel per screen pixel: the 5x7 version lost letters at the 480x270 render size.
    x, y, w, h = region("open_sign", 112, 152, 19, 9)
    atlas.rect(x, y, w, h, C(255, 255, 255))
    atlas.outline(x, y, w, h, C(200, 30, 40))
    atlas.text(x + 2, y + 2, "OPEN", C(220, 30, 40), font="3x5")

    # Stall number plate.
    x, y, w, h = region("stall_no", 142, 152, 30, 11)
    atlas.rect(x, y, w, h, C(250, 250, 245))
    atlas.text_c(x + w // 2, y + 3, "01-17", C(30, 30, 30), font="3x5")

    # Stock on shelves: rows of cans and boxes.
    x, y, w, h = region("stock", 172, 152, 48, 24)
    atlas.rect(x, y, w, h, C(214, 212, 204))
    cols = [C(210, 40, 60), C(60, 160, 70), C(240, 240, 230), C(250, 200, 40), C(60, 110, 200)]
    for row in range(2):
        for i in range(8):
            c = cols[(i * 3 + row) % 5]
            atlas.rect(x + 1 + i * 6, y + 2 + row * 12, 5, 9, c)
            atlas.rect(x + 1 + i * 6, y + 2 + row * 12, 5, 1, C(200, 204, 208))
            atlas.rect(x + 1 + i * 6, y + 5 + row * 12, 5, 2, C(255, 255, 255))
        atlas.rect(x, y + 11 + row * 12, w, 1, C(150, 150, 150))

    # Glass-door drinks fridge front (glow material).
    x, y, w, h = region("fridge", 220, 152, 32, 48)
    atlas.rect(x, y, w, h, C(240, 240, 236))
    atlas.rect(x + 2, y + 6, w - 4, h - 8, C(200, 230, 240))
    atlas.rect(x + 2, y + 1, w - 4, 4, C(40, 110, 200))
    bottle = [C(210, 40, 60), C(250, 140, 30), C(60, 160, 70), C(250, 220, 80), C(140, 200, 230)]
    for shelf in range(4):
        sy = y + 8 + shelf * 10
        for i in range(6):
            atlas.rect(x + 4 + i * 4, sy + 1, 3, 7, bottle[(i + shelf) % 5])
            atlas.rect(x + 5 + i * 4, sy, 1, 1, C(240, 240, 240))
        atlas.rect(x + 2, sy + 8, w - 4, 1, C(170, 180, 186))

    # Roller shutter.
    x, y, w, h = region("shutter", 0, 184, 32, 32)
    for yy in range(h):
        atlas.rect(x, y + yy, w, 1, C(176, 180, 182) if yy % 3 else C(130, 134, 138))

    # Uncle's face: specs, kind eyes, grey brows, moustache-less smile (16x16).
    x, y, w, h = region("uncle_face", 32, 184, 16, 16)
    atlas.rect(x, y, w, h, C(214, 160, 118))
    atlas.rect(x, y, w, 3, C(150, 150, 150))                    # hairline
    atlas.rect(x + 2, y + 4, 4, 1, C(120, 120, 120))            # brows
    atlas.rect(x + 10, y + 4, 4, 1, C(120, 120, 120))
    atlas.outline(x + 1, y + 5, 6, 4, C(20, 20, 22))            # specs
    atlas.outline(x + 9, y + 5, 6, 4, C(20, 20, 22))
    atlas.rect(x + 7, y + 6, 2, 1, C(20, 20, 22))
    atlas.rect(x + 3, y + 6, 2, 2, C(40, 30, 30))               # eyes
    atlas.rect(x + 11, y + 6, 2, 2, C(40, 30, 30))
    atlas.rect(x + 7, y + 9, 2, 2, C(190, 136, 98))             # nose
    atlas.rect(x + 5, y + 12, 6, 1, C(150, 70, 60))             # smile
    atlas.px(x + 4, y + 11, C(150, 70, 60))
    atlas.px(x + 11, y + 11, C(150, 70, 60))
    atlas.rect(x + 2, y + 10, 2, 1, C(226, 140, 110))           # cheeks
    atlas.rect(x + 12, y + 10, 2, 1, C(226, 140, 110))

    # Singlet front: white with skin scoop neck and straps.
    x, y, w, h = region("singlet", 48, 184, 16, 16)
    atlas.rect(x, y, w, h, C(246, 246, 242))
    atlas.rect(x, y, 3, 6, C(214, 160, 118))
    atlas.rect(x + 13, y, 3, 6, C(214, 160, 118))
    atlas.ellipse(x + 8, y, 4, 4, C(214, 160, 118))
    atlas.noise(x, y + 4, w, h - 4, 0.06, 3)

    # Apron: navy with white pinstripes and a pocket.
    x, y, w, h = region("apron", 64, 184, 16, 16)
    atlas.rect(x, y, w, h, C(40, 60, 120))
    for xx in range(1, w, 4):
        atlas.rect(x + xx, y, 1, h, C(200, 210, 230))
    atlas.rect(x + 4, y + 9, 8, 5, C(50, 74, 140))
    atlas.outline(x + 4, y + 9, 8, 5, C(200, 210, 230))

    # Back of uncle's head: grey hair.
    x, y, w, h = region("hair_back", 80, 184, 8, 8)
    atlas.rect(x, y, w, h, C(150, 150, 150))
    atlas.rect(x, y + 6, w, 2, C(214, 160, 118))

    # Wall clock.
    x, y, w, h = region("clock", 88, 184, 16, 16)
    atlas.rect(x, y, w, h, C(214, 212, 204))
    atlas.ellipse(x + 7.5, y + 7.5, 7.5, 7.5, C(200, 40, 40))
    atlas.ellipse(x + 7.5, y + 7.5, 6, 6, C(250, 250, 245))
    atlas.rect(x + 7, y + 3, 1, 5, C(20, 20, 20))
    atlas.rect(x + 7, y + 7, 4, 1, C(20, 20, 20))

    # Hall vents above the stalls: bright sky between louvres (sunny day, glow).
    x, y, w, h = region("vent", 104, 184, 32, 16)
    atlas.rect(x, y, w, h, C(150, 210, 250))
    for yy in range(0, h, 4):
        atlas.rect(x, y + yy, w, 2, C(225, 228, 226))
    for xx in (0, 15, 31):
        atlas.rect(x + xx, y, 1, h, C(200, 200, 196))

    # Floor band: light-grey stepped strip in front of the stalls (ref 05).
    x, y, w, h = region("floor_band", 136, 184, 32, 16)
    atlas.rect(x, y, w, h, C(86, 88, 94))
    for ty in range(0, h, 4):
        for tx in range(0, w, 4):
            light = (tx // 4 + ty // 4) % 2 == 0 and ty // 4 in (1, 2)
            c = C(190, 192, 194) if light else C(96, 98, 104)
            atlas.rect(x + tx, y + ty, 3, 3, c)
            atlas.rect(x + tx + 3, y + ty, 1, 4, C(150, 152, 154))
            atlas.rect(x + tx, y + ty + 3, 4, 1, C(150, 152, 154))
    atlas.noise(x, y, w, h, 0.1, 4)

    # Topping tub contents seen from above (one cell each), colours from data/recipes.json.
    tubs = [("tub_" + t, INGREDIENTS[t]["color"], INGREDIENTS[t]["color2"]) for t in TOPPINGS]
    tubs.append(("tub_tausuan", (232, 210, 120), (210, 180, 90)))
    for i, (name, a, b) in enumerate(tubs):
        x, y, w, h = region(name, 168 + (i % 4) * 8, 184 + (i // 4) * 8, 8, 8)
        atlas.rect(x, y, w, h, C(*a))
        for _ in range(12):
            atlas.px(x + rng.randrange(8), y + rng.randrange(8), C(*b))

    # Labels for the milk cans and coconut carton (wrapped round the side).
    x, y, w, h = region("can_evap_milk", 32, 200, 16, 8)
    atlas.rect(x, y, w, h, C(40, 90, 180))
    atlas.rect(x, y + 3, w, 3, C(250, 250, 240))
    atlas.rect(x + 2, y + 4, 4, 1, C(200, 40, 40))
    atlas.rect(x + 10, y + 4, 4, 1, C(200, 40, 40))
    x, y, w, h = region("can_condensed_milk", 48, 200, 16, 8)
    atlas.rect(x, y, w, h, C(250, 236, 196))
    atlas.rect(x, y + 1, w, 2, C(200, 40, 40))
    atlas.rect(x + 3, y + 4, 10, 3, C(60, 140, 220))
    x, y, w, h = region("carton_coconut_milk", 64, 200, 16, 8)
    atlas.rect(x, y, w, h, C(250, 250, 244))
    atlas.rect(x, y + 5, w, 3, C(60, 160, 80))
    atlas.ellipse(x + 8, y + 3, 2, 2, C(120, 80, 40))


# Customer types (M4). lower: "pants", "shorts" (bare shins) or "skirt". long = long sleeves.
# The game reads the type ids from the cust_<id> objects (scripts/customers/customer_queue.gd).
CUSTOMERS = {
    "office_man":  dict(skin="c_skin_lt", hair="c_hair_black", hair_style="short", top="c_shirt",
                        lower="pants", bottom="c_navy", shoes="c_shoe_black", long=True),
    "auntie":      dict(skin="c_skin_md", hair="c_hair_black", hair_style="perm", top="c_floral",
                        lower="pants", bottom="c_black", shoes="c_sandal", extra=("handbag",)),
    "schoolboy":   dict(skin="c_skin_lt", hair="c_hair_black", hair_style="short", top="c_shirt",
                        lower="shorts", bottom="c_navy", shoes="c_shoe_white", scale=0.8, extra=("backpack",)),
    "office_lady": dict(skin="c_skin_lt", hair="c_hair_brown", hair_style="bun", top="c_blazer",
                        lower="skirt", bottom="c_skirt", shoes="c_shoe_black", long=True),
    "grandpa":     dict(skin="c_skin_dk", hair="c_hair_white", hair_style="short", top="c_polo",
                        lower="pants", bottom="c_khaki", shoes="slipper"),
    "teen_girl":   dict(skin="c_skin_md", hair="c_hair_black", hair_style="ponytail", top="c_lilac",
                        lower="shorts", bottom="c_denim", shoes="c_shoe_white"),
    "worker":      dict(skin="c_skin_dk", hair="c_hair_black", hair_style="hardhat", top="c_hivis",
                        sleeves="c_work_grey", lower="pants", bottom="c_work_grey", shoes="c_boot"),
    "grandma":     dict(skin="c_skin_md", hair="c_hair_grey", hair_style="bun", top="c_samfu",
                        lower="pants", bottom="c_samfu", shoes="slipper", long=True),
}


def _pc(name, k=1.0):
    r, g, b = PALETTE[name]
    return C(min(int(r * k), 255), min(int(g * k), 255), min(int(b * k), 255))


def paint_customers():
    """16x16 face and shirt-front per customer type, in the free atlas rows 208-240."""
    for i, (cid, p) in enumerate(CUSTOMERS.items()):
        paint_customer_face(cid, p, *region("cface_" + cid, 32 + i * 16, 208, 16, 16))
        paint_customer_front(cid, p, *region("cfront_" + cid, 32 + i * 16, 224, 16, 16))


def paint_customer_face(cid, p, x, y, w, h):
    skin, hair = _pc(p["skin"]), _pc(p["hair"])
    shade = _pc(p["skin"], 0.82)
    dark = C(30, 22, 24)
    old = cid in ("grandpa", "grandma")
    lady = cid in ("auntie", "office_lady", "teen_girl", "grandma")
    atlas.rect(x, y, w, h, skin)
    style = p["hair_style"]
    if style == "hardhat":
        atlas.rect(x, y, w, 2, hair)
    elif style == "perm":
        atlas.rect(x, y, w, 4, hair)
        atlas.rect(x, y, 2, 10, hair)
        atlas.rect(x + 14, y, 2, 10, hair)
        for k in range(1, 15, 3):
            atlas.px(x + k, y + 4, hair)
    elif lady:
        atlas.rect(x, y, w, 3, hair)
        atlas.rect(x, y, 2, 8, hair)
        atlas.rect(x + 14, y, 2, 8, hair)
        atlas.rect(x + 2, y + 3, 5, 1, hair)        # side-swept fringe
    else:
        atlas.rect(x, y, w, 3, hair)
        atlas.rect(x, y, 1, 6, hair)
        atlas.rect(x + 15, y, 1, 6, hair)
        atlas.rect(x + 3, y + 3, 4, 1, hair)
    brow = _pc(p["hair"], 0.7) if p["hair"] in ("c_hair_white", "c_hair_grey") else hair
    atlas.rect(x + 3, y + 5, 3, 1, brow)
    atlas.rect(x + 10, y + 5, 3, 1, brow)
    atlas.rect(x + 4, y + 7, 2, 2, dark)
    atlas.rect(x + 10, y + 7, 2, 2, dark)
    if lady:                                        # lashes
        atlas.px(x + 3, y + 7, dark)
        atlas.px(x + 12, y + 7, dark)
    atlas.rect(x + 7, y + 10, 2, 1, shade)          # nose
    if old:                                         # smile lines and crow's feet
        atlas.px(x + 2, y + 8, shade)
        atlas.px(x + 13, y + 8, shade)
        atlas.px(x + 4, y + 11, shade)
        atlas.px(x + 11, y + 11, shade)
    if cid == "grandpa":                            # brown-rim specs
        atlas.outline(x + 2, y + 6, 5, 4, C(90, 60, 40))
        atlas.outline(x + 9, y + 6, 5, 4, C(90, 60, 40))
        atlas.rect(x + 7, y + 7, 2, 1, C(90, 60, 40))
    lips = C(200, 50, 70) if cid in ("office_lady", "auntie") else C(150, 70, 62)
    if cid == "schoolboy":                          # big grin with teeth
        atlas.rect(x + 5, y + 12, 6, 2, C(120, 40, 40))
        atlas.rect(x + 6, y + 12, 4, 1, C(250, 250, 250))
    else:
        atlas.rect(x + 6, y + 12, 4, 1, lips)
        atlas.px(x + 5, y + 11, lips)
        atlas.px(x + 10, y + 11, lips)
    if cid in ("teen_girl", "schoolboy", "grandma", "auntie"):
        atlas.rect(x + 2, y + 10, 2, 1, C(232, 130, 110))
        atlas.rect(x + 12, y + 10, 2, 1, C(232, 130, 110))
    if cid == "worker":                             # stubble
        for k in range(4, 12, 2):
            atlas.px(x + k, y + 14, shade)
            atlas.px(x + k + 1, y + 13, shade)


def paint_customer_front(cid, p, x, y, w, h):
    """Torso front, top row = shoulders."""
    top, skin = _pc(p["top"]), _pc(p["skin"])
    atlas.rect(x, y, w, h, top)
    r = random.Random(sum(map(ord, cid)))   # same pattern every build
    if cid == "office_man":
        atlas.rect(x + 5, y, 2, 2, C(210, 214, 220))          # collar points
        atlas.rect(x + 9, y, 2, 2, C(210, 214, 220))
        atlas.rect(x + 7, y + 1, 2, 2, C(150, 24, 34))         # tie knot
        atlas.rect(x + 7, y + 3, 2, 10, C(180, 30, 40))
        atlas.px(x + 7, y + 13, C(180, 30, 40))
        atlas.outline(x + 2, y + 5, 3, 3, C(200, 204, 212))     # pocket
        atlas.rect(x, y + 15, w, 1, C(30, 30, 34))             # belt
    elif cid == "auntie":
        atlas.ellipse(x + 8, y, 3, 2, skin)
        for _ in range(9):
            fx, fy = x + r.randrange(1, 15), y + r.randrange(3, 15)
            col = C(255, 220, 80) if r.random() < 0.5 else C(255, 245, 240)
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                atlas.px(fx + dx, fy + dy, col)
            atlas.px(fx, fy, C(250, 140, 40))
    elif cid == "schoolboy":
        atlas.rect(x + 5, y, 2, 2, C(210, 214, 220))
        atlas.rect(x + 9, y, 2, 2, C(210, 214, 220))
        for k in (4, 7, 10, 13):
            atlas.px(x + 8, y + k, C(170, 176, 186))
        atlas.rect(x + 10, y + 4, 3, 3, C(40, 70, 170))         # school badge
        atlas.px(x + 11, y + 5, C(250, 210, 60))
    elif cid == "office_lady":
        atlas.rect(x + 5, y, 6, h, C(246, 246, 250))           # blouse between the lapels
        for k in range(5):
            atlas.px(x + 5 + k // 2, y + 5 + k, top)
            atlas.px(x + 10 - k // 2, y + 5 + k, top)
        atlas.rect(x + 4, y, 1, 9, C(200, 40, 50))              # lanyard + pass
        atlas.rect(x + 11, y, 1, 9, C(200, 40, 50))
        atlas.rect(x + 6, y + 9, 4, 5, C(250, 250, 250))
        atlas.rect(x + 7, y + 10, 2, 2, C(60, 120, 200))
    elif cid == "grandpa":
        atlas.rect(x + 4, y, 8, 2, _pc(p["top"], 0.75))         # collar
        atlas.rect(x + 7, y + 2, 2, 5, _pc(p["top"], 0.85))     # placket
        atlas.px(x + 7, y + 3, C(245, 245, 240))
        atlas.px(x + 7, y + 5, C(245, 245, 240))
        atlas.rect(x + 11, y + 4, 2, 2, C(250, 220, 80))         # little logo
    elif cid == "teen_girl":
        atlas.ellipse(x + 8, y, 3, 2, skin)
        for dx, dy in ((-2, 0), (-1, -1), (0, 0), (1, -1), (2, 0), (-2, 1), (2, 1),
                       (-1, 2), (1, 2), (0, 3), (-1, 0), (0, 1), (1, 0), (-1, 1), (1, 1), (0, 2)):
            atlas.px(x + 8 + dx, y + 8 + dy, C(240, 90, 150))
    elif cid == "worker":
        grey = _pc("c_work_grey")
        atlas.rect(x + 5, y, 6, 3, grey)                        # shirt at the neck
        for sy in (8, 12):                                      # reflective strips
            atlas.rect(x, y + sy, w, 2, C(230, 236, 200))
        atlas.rect(x + 7, y + 3, 1, 13, C(120, 60, 10))          # zip
    elif cid == "grandma":
        atlas.rect(x + 4, y, 8, 2, _pc(p["top"], 0.7))          # mandarin collar
        for _ in range(10):
            atlas.px(x + r.randrange(0, 16), y + r.randrange(2, 16), C(245, 248, 255))
        for k in range(4):                                      # frog buttons, diagonal
            atlas.rect(x + 8 + k * 2, y + 3 + k * 3, 2, 1, C(250, 250, 250))
    atlas.noise(x, y, w, h, 0.06, 11)


def paint_floor_and_walls():
    # Floor: dark-grey square tiles, 4 x 4 per texture (0.3 m each), slight variation.
    fl = Canvas(64, 64, (80, 82, 88))
    for ty in range(4):
        for tx in range(4):
            v = rng.randrange(-8, 9)
            fl.rect(tx * 16, ty * 16, 16, 16, C(84 + v, 86 + v, 92 + v))
            fl.rect(tx * 16, ty * 16, 16, 1, C(120, 122, 124))
            fl.rect(tx * 16, ty * 16, 1, 16, C(120, 122, 124))
    fl.noise(0, 0, 64, 64, 0.12, 5)
    fl.save(os.path.join(TEX_DIR, "floor.png"))

    # Wall: small white glazed tiles with grey grout, 6 x 6 per texture (0.1 m each).
    wl = Canvas(48, 48, (180, 182, 180))
    for ty in range(6):
        for tx in range(6):
            v = rng.randrange(-5, 6)
            wl.rect(tx * 8 + 1, ty * 8 + 1, 7, 7, C(222 + v, 224 + v, 220 + v))
            wl.px(tx * 8 + 2, ty * 8 + 2, C(255, 255, 255))
    wl.save(os.path.join(TEX_DIR, "walltile.png"))


# ---------------------------------------------------------------------------
# Mesh builder: flat-shaded quads/tris, per-face material + UV
# ---------------------------------------------------------------------------

FACE_CORNERS = {
    # BL, BR, TR, TL as seen from outside the face; unit box corners
    "front": [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
    "back": [(1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)],
    "left": [(-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)],
    "right": [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
    "top": [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
    "bottom": [(-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)],
}


class Builder:
    def __init__(self):
        self.verts, self.faces, self.uvs, self.mats = [], [], [], []
        self.mat_names = []
        self.stack = [Matrix.Identity(4)]

    # transform stack -------------------------------------------------------
    def push(self, m):
        self.stack.append(self.stack[-1] @ m)

    def pop(self):
        self.stack.pop()

    def at(self, pos, rot_z=0.0, rot_x=0.0):
        self.push(Matrix.Translation(Vector(pos)) @ Matrix.Rotation(math.radians(rot_z), 4, "Z")
                  @ Matrix.Rotation(math.radians(rot_x), 4, "X"))
        return self

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.pop()

    # primitives -------------------------------------------------------------
    def _mat_index(self, name):
        if name not in self.mat_names:
            self.mat_names.append(name)
        return self.mat_names.index(name)

    def poly(self, pts, look, mat=None):
        """pts in local coords (BL, BR, TR, TL order for quads). look = swatch name or
        ('region', name[, flip_x]). mat defaults to atlas (or walltile/floor for those looks)."""
        m = self.stack[-1]
        w = [m @ Vector(p) for p in pts]
        if mat is None:
            mat = look if look in REPEAT_MATS else "atlas"
        if mat in REPEAT_MATS:
            tile = REPEAT_MATS[mat]
            if mat == "floor":
                uv = [(p.x / tile, p.y / tile) for p in w]
            else:
                ua = (w[1] - w[0]).normalized()
                va = (w[-1] - w[0]).normalized()
                uv = [(p.dot(ua) / tile, p.dot(va) / tile) for p in w]
        elif isinstance(look, tuple):
            rx, ry, rw, rh = REGIONS[look[1]]
            flip = len(look) > 2 and look[2]
            u0, u1 = (rx + 0.01) / ATLAS_W, (rx + rw - 0.01) / ATLAS_W
            if flip:
                u0, u1 = u1, u0
            v0, v1 = 1 - (ry + rh - 0.01) / ATLAS_H, 1 - (ry + 0.01) / ATLAS_H
            if len(pts) == 4:
                uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            else:  # round cap etc: planar fit of the polygon's bounding box onto the region
                ua = (w[1] - w[0]).normalized()
                va = (w[1] - w[0]).cross(w[2] - w[0]).normalized().cross(ua)
                ps = [(p.dot(ua), p.dot(va)) for p in w]
                mu, mv = min(p[0] for p in ps), min(p[1] for p in ps)
                su = max(p[0] for p in ps) - mu or 1
                sv = max(p[1] for p in ps) - mv or 1
                uv = [(u0 + (u1 - u0) * (pu - mu) / su, v0 + (v1 - v0) * (pv - mv) / sv) for pu, pv in ps]
        else:
            uv = [SWATCH[look]] * len(pts)
        base = len(self.verts)
        self.verts.extend(w)
        self.faces.append(list(range(base, base + len(pts))))
        self.uvs.append(uv)
        self.mats.append(self._mat_index(mat))

    def box(self, lo, hi, look="white", faces=None, skip=(), mat=None):
        """Axis-aligned box from corner lo to corner hi (local coords).
        faces: {face_name: look} overrides; skip: faces to leave out."""
        lo, hi = Vector(lo), Vector(hi)
        c, hs = (lo + hi) / 2, (hi - lo) / 2
        faces = faces or {}
        for fname, corners in FACE_CORNERS.items():
            if fname in skip:
                continue
            pts = [(c.x + hs.x * a, c.y + hs.y * b, c.z + hs.z * d) for a, b, d in corners]
            f = faces.get(fname, look)
            fm = mat
            if isinstance(f, list):     # [look, material]
                f, fm = f
            self.poly(pts, f, fm)

    def frustum(self, z0, z1, w0, d0, w1, d1, look, faces=None, skip=()):
        """Box tapering from (w0, d0) at z0 to (w1, d1) at z1, centred on local origin."""
        faces = faces or {}
        def p(sx, sy, top):
            w, d, z = (w1, d1, z1) if top else (w0, d0, z0)
            return (sx * w / 2, sy * d / 2, z)
        quads = {
            "front": [p(-1, -1, 0), p(1, -1, 0), p(1, -1, 1), p(-1, -1, 1)],
            "back": [p(1, 1, 0), p(-1, 1, 0), p(-1, 1, 1), p(1, 1, 1)],
            "left": [p(-1, 1, 0), p(-1, -1, 0), p(-1, -1, 1), p(-1, 1, 1)],
            "right": [p(1, -1, 0), p(1, 1, 0), p(1, 1, 1), p(1, -1, 1)],
            "top": [p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)],
            "bottom": [p(-1, 1, 0), p(1, 1, 0), p(1, -1, 0), p(-1, -1, 0)],
        }
        for fname, pts in quads.items():
            if fname not in skip:
                self.poly(pts, faces.get(fname, look))

    def cyl(self, base, r_bot, r_top, h, look, segs=8, caps=(False, True), top_look=None, mat=None, inside=False):
        """inside=True: the wall faces inwards (inner wall of a bowl or pot)."""
        bx, by, bz = base
        ring = [(math.cos(2 * math.pi * i / segs), math.sin(2 * math.pi * i / segs)) for i in range(segs)]
        for i in range(segs):
            (c0, s0), (c1, s1) = ring[i], ring[(i + 1) % segs]
            if r_top <= 0.0001:
                pts = [(bx + c0 * r_bot, by + s0 * r_bot, bz), (bx + c1 * r_bot, by + s1 * r_bot, bz), (bx, by, bz + h)]
            else:
                pts = [(bx + c0 * r_bot, by + s0 * r_bot, bz), (bx + c1 * r_bot, by + s1 * r_bot, bz),
                       (bx + c1 * r_top, by + s1 * r_top, bz + h), (bx + c0 * r_top, by + s0 * r_top, bz + h)]
            self.poly(pts[::-1] if inside else pts, look, mat)
        if caps[1] and r_top > 0.0001:
            self.poly([(bx + c * r_top, by + s * r_top, bz + h) for c, s in ring], top_look or look, mat)
        if caps[0]:
            self.poly([(bx + c * r_bot, by + s * r_bot, bz) for c, s in reversed(ring)], look, mat)

    def dome(self, base, r, h, look, segs=8, rings=3):
        """Shaved-ice style mound: stacked rings closing to a point."""
        bx, by, bz = base
        prev_r, prev_z = r, bz
        for k in range(1, rings + 1):
            t = k / rings
            nr = r * math.cos(t * math.pi / 2) if k < rings else 0.0
            nz = bz + h * math.sin(t * math.pi / 2)
            self.cyl((bx, by, prev_z), prev_r, nr, nz - prev_z, look, segs, caps=(False, False))
            prev_r, prev_z = nr, nz

    # output -----------------------------------------------------------------
    def to_object(self, name, origin=(0, 0, 0), parent=None):
        o = Vector(origin)
        me = bpy.data.meshes.new(name)
        me.from_pydata([v - o for v in self.verts], [], self.faces)
        uvl = me.uv_layers.new(name="UVMap")
        li = 0
        for poly, uv in zip(me.polygons, self.uvs):
            for k in range(poly.loop_total):
                uvl.data[poly.loop_start + k].uv = uv[k]
        for n in self.mat_names:
            me.materials.append(get_material(n))
        for poly, mi in zip(me.polygons, self.mats):
            poly.material_index = mi
            poly.use_smooth = False
        me.validate()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = o
        if parent is not None:
            ob.parent = parent
            ob.location = o - Vector(parent.location)  # matrix_world is stale until a depsgraph update
        return ob


PREVIEW = {"atlas": (0.8, 0.8, 0.8), "glow": (1, 1, 1), "floor": (0.3, 0.3, 0.32),
           "walltile": (0.9, 0.9, 0.9), "glass": (0.7, 0.9, 1.0), "bowlglass": (0.6, 0.88, 0.92)}


def get_material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*PREVIEW.get(name, (1, 0, 1)), 1)
    return m


# ---------------------------------------------------------------------------
# Scene layout (ref 05)
# ---------------------------------------------------------------------------

UNIT_W = 4.2         # stall unit width
UNIT_D = 3.0         # depth to the back wall
PART = 0.3           # partition wall thickness
UNIT_TOP = 3.15      # top of signboard
INNER_CEIL = 2.6
HALL_CEIL = 4.0

# Making station on the work bench (bench: x -1.95..0.45, y 1.35..1.95, top BENCH_Z).
# Everything the player touches must fit the making camera, so the station is compact.
# The making camera looks towards the customers (-Y), so +X is on the LEFT of the screen:
# the flow bowls -> shaver -> tubs -> sauces -> bin reads left to right with falling X.
BENCH_Z = 0.93
SHAVER = (-0.02, 1.6)               # base centre; the bowl sits on the base under the drum
BOWL_STACK = (0.32, 1.5)
ICE_TRAY = (-0.37, 1.83)            # plain + milk ice blocks, behind the first tubs
TUB_X0, TUB_DX = -0.42, -0.13       # 4 x 2 topping tubs, slot = row * 4 + col
TUB_Y = (1.45, 1.61)
SAUCE_X0, SAUCE_DX, SAUCE_Y = -0.56, -0.085, 1.86
BIN = (0.32, 1.8)                   # scrap pail, front left
# Soup corner at the right end of the bench (M6): pot on a burner at the back, you tiao plate
# between the tubs and the pot, soup bowls front right, the bowl being filled in front of the pot.
SOUP_POT = (-1.25, 1.52)
YOU_TIAO = (-0.98, 1.44)
SOUP_SPOT = (-1.0, 1.7)
SOUP_BOWLS = (-1.24, 1.84)
BOWL_R = 0.12                       # glass bowl rim radius (game: scripts/making/bowl.gd)
SOUP_R = 0.1                        # soup bowl rim radius (game: Bowl.SOUP_*)
SERVE_TRAY = (-0.5, 0.55)           # on top of the display case (z 1.34)

# Camera views, read by Godot from the cam_<view> and cam_<view>_target markers. The vertical
# FOV lives in scripts/stall.gd (VIEW_FOV); keep it in sync with the preview render here.
CAMERAS = {
    "waiting": ((0.0, -5.4, 2.0), (0.0, 0.0, 1.45), 46),
    "making": ((-0.45, 2.55, 1.95), (-0.45, 1.3, 1.0), 50),
}


def build_hall(b):
    # Floor plane (big), plus the light-grey band in front of the stall row.
    b.poly([(-16, -14, 0), (16, -14, 0), (16, UNIT_D, 0), (-16, UNIT_D, 0)], "floor", "floor")
    for i in range(-11, 11):
        x0 = i * 0.6
        b.poly([(x0, -0.9, 0.003), (x0 + 0.6, -0.9, 0.003), (x0 + 0.6, -0.1, 0.003), (x0, -0.1, 0.003)],
               ("region", "floor_band"))
    # Kerb step along the stall fronts.
    b.box((-12.6, -0.1, 0), (12.6, 0.02, 0.04), "kerb")
    # Bulkhead wall above the stall row, with sunny vents.
    b.box((-12.6, -0.05, UNIT_TOP), (12.6, 0.15, HALL_CEIL), "hall_wall", skip=("bottom",))
    for i in range(-5, 5):
        x0 = i * 2.4 + 0.3
        b.poly([(x0, -0.06, 3.35), (x0 + 1.8, -0.06, 3.35), (x0 + 1.8, -0.06, 3.85), (x0, -0.06, 3.85)],
               ("region", "vent"), "glow")
    # Hall columns (orange-tiled lower half, like many hawker centres).
    for x, y in ((-8.0, -5.5), (8.0, -5.5)):
        b.box((x - 0.3, y - 0.3, 0), (x + 0.3, y + 0.3, 1.4), "orange", skip=("bottom",))
        b.box((x - 0.3, y - 0.3, 1.4), (x + 0.3, y + 0.3, HALL_CEIL), "pillar", skip=("bottom", "top"))
    # Round hawker tables with fixed stools, out in the seating area.
    for x, y in ((-4.6, -4.2), (4.8, -4.4), (-2.0, -8.5), (2.4, -8.6), (-6.5, -8.0), (6.8, -8.2)):
        b.cyl((x, y, 0), 0.08, 0.06, 0.72, "steel_dark", segs=6, caps=(False, False))
        b.cyl((x, y, 0.72), 0.55, 0.55, 0.05, "table_top", segs=12)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            sx, sy = x + math.cos(a) * 0.8, y + math.sin(a) * 0.8
            b.cyl((sx, sy, 0), 0.04, 0.04, 0.42, "steel_dark", segs=5, caps=(False, False))
            b.cyl((sx, sy, 0.42), 0.17, 0.17, 0.04, "stool_red", segs=8)


def build_roof(b):
    b.box((-16, -14, HALL_CEIL), (16, 0.2, HALL_CEIL + 0.1), "ceiling")
    for y in (-2.0, -6.0, -10.0):     # ceiling beams
        b.box((-16, y - 0.15, HALL_CEIL - 0.35), (16, y + 0.15, HALL_CEIL), "beam", skip=("top",))


def build_lights(b):
    # Fluorescent tubes hanging in the hall.
    for y in (-3.6, -7.8):
        for x in (-6.0, -2.0, 2.0, 6.0):
            b.box((x - 0.6, y - 0.05, 3.5), (x + 0.6, y + 0.05, 3.56), "tube", mat="glow")
            b.box((x - 0.02, y - 0.02, 3.56), (x + 0.02, y + 0.02, HALL_CEIL - 0.35), "steel_dark")


def build_unit_shell(b, x0, sign, menu, sign_col):
    """One stall unit between x0 and x0 + UNIT_W: walls, inner ceiling, signboard, lightbox."""
    x1 = x0 + UNIT_W
    # back wall and inner ceiling
    b.box((x0, UNIT_D, 0), (x1, UNIT_D + 0.1, INNER_CEIL), "walltile", skip=("back", "bottom"))
    b.box((x0, 0.1, INNER_CEIL), (x1, UNIT_D, INNER_CEIL + 0.05), "ceiling", skip=("top",))
    # fascia between inner ceiling and signboard
    b.box((x0, -0.02, INNER_CEIL - 0.05), (x1, 0.15, UNIT_TOP), sign_col, skip=("bottom", "back"))
    # signboard, slightly proud of the fascia
    b.box((x0 + 0.08, -0.16, 2.62), (x1 - 0.08, -0.02, UNIT_TOP - 0.02), sign_col,
          faces={"front": ("region", sign)})
    # tube light under the signboard
    b.box((x0 + 0.5, -0.06, 2.55), (x1 - 0.5, 0.0, 2.6), "tube", mat="glow")
    # lightbox menu, hanging and tilted down towards customers
    if menu:
        cx = (x0 + x1) / 2
        with b.at((cx, 0.1, 2.27), rot_x=-12):
            hw = UNIT_W / 2 - 0.3
            b.box((-hw, -0.05, -0.28), (hw, 0.05, 0.28), "lightbox_back",
                  faces={"front": [("region", menu), "glow"]})
        b.box((cx - 0.8, 0.1, 2.52), (cx - 0.78, 0.12, INNER_CEIL), "steel_dark")
        b.box((cx + 0.78, 0.1, 2.52), (cx + 0.8, 0.12, INNER_CEIL), "steel_dark")


def build_partition(b, x):
    b.box((x - PART / 2, -0.05, 0), (x + PART / 2, UNIT_D, UNIT_TOP), "walltile", skip=("bottom", "top", "back"))


def build_our_stall(b):
    x0 = -UNIT_W / 2
    build_unit_shell(b, x0, "sign_ours", "menu_ours", "sign_pink")
    # stall number plate on the left partition
    b.poly([(x0 - 0.12, -0.06, 2.3), (x0 + 0.12, -0.06, 2.3), (x0 + 0.12, -0.06, 2.39), (x0 - 0.12, -0.06, 2.39)],
           ("region", "stall_no"))
    # inner tube light
    b.box((-1.0, 1.4, INNER_CEIL - 0.06), (1.0, 1.5, INNER_CEIL), "tube", mat="glow")

    # --- glass display counter, left ~60% of the front (ref 05) ---
    dx0, dx1, dy0, dy1 = -1.95, 0.45, 0.12, 0.92
    b.box((dx0, dy0, 0), (dx1, dy1, 0.08), "black", skip=("bottom",))                  # plinth
    b.box((dx0, dy0, 0.08), (dx1, dy1, 0.78), "steel",
          faces={"front": ("region", "poster_fruit")}, skip=("bottom",))
    b.box((dx0 - 0.02, dy0 - 0.02, 0.78), (dx1 + 0.02, dy1 + 0.02, 0.82), "glass_frame")
    for px_ in (dx0, dx1 - 0.04):
        for py_ in (dy0, dy1 - 0.04):
            b.box((px_, py_, 0.82), (px_ + 0.04, py_ + 0.04, 1.3), "glass_frame", skip=("bottom", "top"))
    b.box((dx0 - 0.02, dy0 - 0.02, 1.3), (dx1 + 0.02, dy1 + 0.02, 1.34), "glass_frame")
    # trays of toppings inside the case
    for i, tub in enumerate(("tub_red_bean", "tub_jelly", "tub_corn", "tub_pandan", "tub_attap", "tub_mango")):
        tx = dx0 + 0.12 + i * 0.38
        b.box((tx, dy0 + 0.25, 0.82), (tx + 0.32, dy0 + 0.6, 0.88), "tub_steel", faces={"top": ("region", tub)})
    # paper menus standing on the counter top (ref 05: menus pasted above the glass). Along the
    # customer edge, so the top behind them is free for the serving tray.
    b.box((dx0, dy0 + 0.02, 1.34), (dx1, dy0 + 0.06, 1.5), "steel")
    for i in range(4):
        px_ = dx0 + 0.1 + i * 0.58
        b.poly([(px_, dy0 + 0.015, 1.37), (px_ + 0.5, dy0 + 0.015, 1.37),
                (px_ + 0.5, dy0 + 0.015, 1.48), (px_, dy0 + 0.015, 1.48)], ("region", "paper"))
    # pink serving tray: the uncle puts finished desserts here for the customer
    tx, ty = SERVE_TRAY
    b.box((tx - 0.17, ty - 0.12, 1.34), (tx + 0.17, ty + 0.12, 1.35), "tray_pink")
    for lo, hi in (((tx - 0.17, ty - 0.12), (tx + 0.17, ty - 0.1)), ((tx - 0.17, ty + 0.1), (tx + 0.17, ty + 0.12)),
                   ((tx - 0.17, ty - 0.1), (tx - 0.15, ty + 0.1)), ((tx + 0.15, ty - 0.1), (tx + 0.17, ty + 0.1))):
        b.box((lo[0], lo[1], 1.35), (hi[0], hi[1], 1.37), "tray_pink", skip=("bottom",))

    # --- OPEN stand and dark cabinet, right of the display (ref 05) ---
    b.box((0.6, 0.2, 0), (1.05, 0.62, 0.8), "cabinet", skip=("bottom",))
    b.box((0.575, 0.3, 0.8), (1.075, 0.36, 1.04), "sign_pink", faces={"front": ("region", "open_sign")})

    # --- folding table with yellow basin, right side (ref 05) ---
    b.box((1.2, 0.25, 0.72), (2.0, 0.85, 0.76), "table_top")
    for lx in (1.25, 1.92):
        for ly in (0.3, 0.77):
            b.box((lx, ly, 0), (lx + 0.03, ly + 0.03, 0.72), "black", skip=("top", "bottom"))
    b.cyl((1.6, 0.55, 0.76), 0.2, 0.26, 0.12, "basin_yellow", segs=10, caps=(False, True), top_look="water")

    # --- work bench behind the display: where the uncle makes desserts ---
    b.box((-1.95, 1.35, 0), (0.45, 1.95, 0.9), "steel", skip=("bottom",))
    b.box((-1.97, 1.33, 0.9), (0.47, 1.97, 0.93), "tub_steel")

    # --- back wall: glass drinks fridge, chest freezer, shelves of stock, clock ---
    b.box((1.15, 2.35, 0), (2.0, 2.95, 1.75), "white",
          faces={"front": [("region", "fridge"), "glow"]}, skip=("bottom", "back"))
    b.box((-1.95, 2.35, 0), (0.0, 2.95, 0.85), "white", skip=("bottom", "back"))           # chest freezer
    b.box((-1.9, 2.4, 0.85), (-0.05, 2.9, 0.88), "steel")
    for z in (1.45, 1.9):
        b.box((-1.9, 2.75, z), (0.6, 3.0, z + 0.03), "steel_dark")
        b.poly([(-1.88, 2.84, z + 0.03), (0.58, 2.84, z + 0.03), (0.58, 2.84, z + 0.33), (-1.88, 2.84, z + 0.33)],
               ("region", "stock"))
    b.poly([(0.7, 2.99, 2.0), (1.0, 2.99, 2.0), (1.0, 2.99, 2.3), (0.7, 2.99, 2.3)], ("region", "clock"))
    # stacked blue stools by the cabinet
    for k in range(3):
        b.cyl((1.5, 1.5, 0.12 * k), 0.17, 0.2, 0.12, "plastic_blue", segs=8, caps=(False, k == 2))


def build_left_neighbour(b):
    x0 = -UNIT_W * 1.5
    build_unit_shell(b, x0, "sign_left", "menu_left", "nb_yellow")
    b.box((x0 + 0.2, 0.15, 0), (x0 + UNIT_W - 0.3, 0.85, 1.0), "steel", skip=("bottom",))
    b.box((x0 + 0.18, 0.13, 1.0), (x0 + UNIT_W - 0.28, 0.87, 1.04), "tub_steel")
    # oranges and limes heaped in trays
    for i in range(10):
        b.cyl((x0 + 0.5 + i * 0.12, 0.4 + (i % 2) * 0.1, 1.04), 0.06, 0.05, 0.08, "orange" if i % 3 else "lime", segs=6)
    # juicer
    b.box((x0 + 2.4, 0.35, 1.04), (x0 + 2.75, 0.65, 1.45), "steel_dark")
    b.cyl((x0 + 2.57, 0.5, 1.45), 0.14, 0.12, 0.12, "glass_frame", segs=8)
    # two glowing drinks fridges on the back wall
    for fx in (x0 + 0.4, x0 + 1.4):
        b.box((fx, 2.35, 0), (fx + 0.85, 2.95, 1.8), "white", faces={"front": [("region", "fridge"), "glow"]},
              skip=("bottom", "back"))
    b.box((x0 + 2.6, 2.75, 1.5), (x0 + 3.9, 3.0, 1.53), "steel_dark")
    b.poly([(x0 + 2.62, 2.84, 1.53), (x0 + 3.88, 2.84, 1.53), (x0 + 3.88, 2.84, 1.83), (x0 + 2.62, 2.84, 1.83)],
           ("region", "stock"))


def build_right_neighbour(b):
    x0 = UNIT_W / 2
    build_unit_shell(b, x0, "sign_right", "menu_right", "nb_orange")
    # roller shutter pulled half down
    b.box((x0 + 0.15, -0.04, 1.35), (x0 + UNIT_W - 0.15, 0.06, INNER_CEIL), "shutter",
          faces={"front": ("region", "shutter")})
    b.box((x0 + 0.15, -0.06, 1.3), (x0 + UNIT_W - 0.15, 0.08, 1.36), "steel_dark")
    b.box((x0 + 0.2, 0.2, 0), (x0 + UNIT_W - 0.3, 0.85, 0.95), "steel", skip=("bottom",))
    b.box((x0 + 0.18, 0.18, 0.95), (x0 + UNIT_W - 0.28, 0.87, 0.98), "tub_steel")
    # big noodle pot and stacked bowls
    b.cyl((x0 + 1.0, 0.55, 0.98), 0.28, 0.3, 0.4, "steel", segs=10, top_look="soup_yellow")
    for k in range(5):
        b.cyl((x0 + 2.2, 0.5, 0.98 + k * 0.04), 0.1, 0.13, 0.04, "bowl_white", segs=8, caps=(False, k == 4))
    b.box((x0 + 0.3, 2.4, 0), (x0 + 3.8, 2.95, 0.9), "steel", skip=("bottom", "back"))


def build_far_units(b):
    """Closed stalls beyond the neighbours so the row continues off-screen."""
    for side in (-1, 1):
        for k in (2,):
            x0 = side * (UNIT_W * (k + 0.5)) - (UNIT_W if side < 0 else 0)
            build_unit_shell(b, x0, "sign_left" if side > 0 else "sign_right", None, "nb_blue" if side > 0 else "nb_green")
            b.box((x0 + 0.1, -0.04, 0), (x0 + UNIT_W - 0.1, 0.06, INNER_CEIL), "shutter",
                  faces={"front": ("region", "shutter")})


def marker(name, pos):
    """Empty exported as a plain Node3D: a named spot the game reads (Godot: (x, z, -y))."""
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = pos
    return o


def build_fan(name, pos):
    b = Builder()
    x, y, z = pos
    b.box((x - 0.015, y - 0.015, z + 0.1), (x + 0.015, y + 0.015, HALL_CEIL - 0.35), "fan_white")
    b.cyl((x, y, z - 0.05), 0.1, 0.1, 0.15, "fan_white", segs=8, caps=(True, True))
    for k in range(3):
        with b.at((x, y, z), rot_z=120 * k):
            b.box((0.08, -0.07, 0.0), (0.75, 0.07, 0.015), "fan_white")
    return b.to_object(name, origin=pos)


def build_props():
    """Making-station props. Things that move are separate objects; fixed things are merged into
    one mesh. Empties named mk_* mark the spots the game needs (see scripts/making/station.gd)."""
    objs = []
    z = BENCH_Z
    # Ice shaver (ref 04: rounded, toy-like, cream frame). The ice drum is its own object so the
    # game can tint it when the milk-ice block is loaded.
    b = Builder()
    sx, sy = SHAVER
    b.cyl((sx, sy, z), 0.2, 0.19, 0.06, "shaver_cream", segs=12)
    # column on the customer side, so it never hides the bowl from the uncle's view
    b.box((sx - 0.07, sy - 0.24, z + 0.06), (sx + 0.07, sy - 0.12, z + 0.62), "shaver_cream")
    b.cyl((sx, sy, z + 0.4), 0.14, 0.17, 0.08, "shaver_cream", segs=12, caps=(True, True))
    b.cyl((sx, sy, z + 0.38), 0.025, 0.04, 0.02, "steel_dark", segs=6, caps=(True, False))   # spout
    b.cyl((sx, sy, z + 0.64), 0.155, 0.155, 0.02, "shaver_cream", segs=12, caps=(True, True))
    b.cyl((sx, sy, z + 0.66), 0.03, 0.03, 0.08, "shaver_cream", segs=6)
    b.box((sx - 0.02, sy - 0.02, z + 0.72), (sx + 0.2, sy + 0.02, z + 0.75), "shaver_cream")
    b.cyl((sx + 0.19, sy, z + 0.75), 0.025, 0.025, 0.08, "plastic_red", segs=6)
    objs.append(b.to_object("shaver", origin=(sx, sy, z)))
    b = Builder()
    b.cyl((sx, sy, z + 0.48), 0.14, 0.14, 0.16, "ice_block", segs=12, caps=(False, False))
    objs.append(b.to_object("shaver_block", origin=(sx, sy, z + 0.48)))
    marker("mk_bowl_spot", (sx, sy, z + 0.06))
    marker("mk_spout", (sx, sy, z + 0.38))
    marker("mk_shaver", (sx, sy, z + 0.52))

    # The working bowl (one at a time; the game moves it around and fills it).
    b = Builder()
    # Tinted see-through walls (outer + inner, own "bowlglass" material) so the ice inside
    # shows; an opaque bright rim and a solid teal foot keep the outline readable.
    b.cyl((0, 0, 0), 0.045, 0.045, 0.03, "glass_foot", segs=8, caps=(True, True))
    # walls ~29 deg off vertical: the making camera looks down at ~45 deg, so a flatter flare
    # would turn the outside of the glass away from it and only the rim would show
    b.cyl((0, 0, 0.03), 0.088, BOWL_R, 0.063, "bowl_glass", segs=10, caps=(True, False), mat="bowlglass")
    b.cyl((0, 0, 0.034), 0.083, BOWL_R - 0.005, 0.059, "bowl_glass", segs=10, caps=(False, False),
          mat="bowlglass", inside=True)
    b.cyl((0, 0, 0.093), BOWL_R, BOWL_R, 0.012, "glass_rim", segs=10, caps=(False, False))
    b.cyl((0, 0, 0.093), BOWL_R - 0.006, BOWL_R - 0.006, 0.012, "glass_rim", segs=10, caps=(False, False),
          inside=True)
    objs.append(b.to_object("bowl"))
    # The soup bowl: white with a blue rim, open so the soup inside shows (Godot draws the soup).
    b = Builder()
    b.cyl((0, 0, 0), 0.045, 0.045, 0.02, "bowl_white", segs=10, caps=(True, False))
    b.cyl((0, 0, 0.02), 0.055, SOUP_R, 0.06, "bowl_white", segs=10, caps=(False, False))
    b.cyl((0, 0, 0.074), SOUP_R, SOUP_R, 0.008, "bowl_rim", segs=10, caps=(False, False))
    b.cyl((0, 0, 0.028), 0.05, SOUP_R - 0.006, 0.054, "offwhite", segs=10, caps=(False, False), inside=True)
    b.cyl((0, 0, 0.026), 0.05, 0.05, 0.002, "offwhite", segs=10)
    objs.append(b.to_object("soup_bowl"))

    # Everything fixed on the bench, merged: bowl stacks, ice tray, tubs, bin, soup corner.
    b = Builder()
    bx, by = BOWL_STACK
    for k in range(4):
        b.cyl((bx, by, z + k * 0.05), 0.095, BOWL_R, 0.04, "bowl_glass", segs=8, caps=(k == 0, False),
              mat="bowlglass")
        b.cyl((bx, by, z + k * 0.05 + 0.04), BOWL_R, BOWL_R, 0.01, "glass_rim", segs=8, caps=(False, False))
        if k == 3:
            b.cyl((bx, by, z + k * 0.05 + 0.004), 0.09, BOWL_R - 0.005, 0.047, "bowl_glass", segs=8,
                  caps=(False, False), mat="bowlglass", inside=True)
    marker("mk_bowl_stack", (bx, by, z + 0.12))
    bx, by = SOUP_BOWLS
    for k in range(4):
        b.cyl((bx, by, z + k * 0.045), 0.055, SOUP_R, 0.045, "bowl_white", segs=8, caps=(False, k == 3))
        b.cyl((bx, by, z + k * 0.045 + 0.039), SOUP_R, SOUP_R, 0.006, "bowl_rim", segs=8, caps=(False, False))
    marker("mk_soup_stack", (bx, by, z + 0.1))
    marker("mk_soup_spot", (SOUP_SPOT[0], SOUP_SPOT[1], z))
    # you tiao on a small steel plate: three long golden sticks
    yx, yy = YOU_TIAO
    b.box((yx - 0.05, yy - 0.08, z), (yx + 0.05, yy + 0.08, z + 0.012), "tub_steel", skip=("bottom",))
    for k, dx in enumerate((-0.028, 0.0, 0.028)):
        look = "you_tiao" if k != 1 else "you_tiao_lt"
        b.box((yx + dx - 0.012, yy - 0.065, z + 0.012), (yx + dx + 0.012, yy + 0.065, z + 0.034), look,
              skip=("bottom",))
    marker("mk_tub_you_tiao", (yx, yy, z + 0.04))
    # ice block tray: plain (left) and milk (right)
    ix, iy = ICE_TRAY
    b.box((ix - 0.13, iy - 0.08, z), (ix + 0.13, iy + 0.08, z + 0.02), "tub_steel", skip=("bottom",))
    for dx, look, kind in ((0.06, "ice_block", "plain"), (-0.06, "milk_block", "milk")):   # +X = screen left
        b.box((ix + dx - 0.045, iy - 0.045, z + 0.02), (ix + dx + 0.045, iy + 0.045, z + 0.1), look,
              skip=("bottom",))
        marker("mk_ice_" + kind, (ix + dx, iy, z + 0.07))
    # topping tubs, 4 x 2
    for t in TOPPINGS:
        slot = INGREDIENTS[t]["slot"]
        tx, ty = TUB_X0 + (slot % 4) * TUB_DX, TUB_Y[slot // 4]
        b.cyl((tx, ty, z), 0.06, 0.065, 0.08, "tub_steel", segs=8, top_look=("region", "tub_" + t))
        marker("mk_tub_" + t, (tx, ty, z + 0.08))
    # scrap pail for binning a bowl
    px_, py_ = BIN
    b.cyl((px_, py_, z), 0.08, 0.1, 0.16, "bin_red", segs=10, top_look="pot_inner")
    b.cyl((px_, py_, z + 0.16), 0.105, 0.105, 0.015, "bin_red", segs=10, caps=(False, False))
    marker("mk_bin", (px_, py_, z + 0.16))
    marker("mk_tray", (SERVE_TRAY[0], SERVE_TRAY[1], 1.35))
    objs.append(b.to_object("station", origin=(0, 0, 0)))

    # Sauces: one object each (they lift, tilt and pour). Origin at the base centre.
    for s in SAUCES:
        info = INGREDIENTS[s]
        sx_ = SAUCE_X0 + info["slot"] * SAUCE_DX
        b = Builder()
        if info["container"] == "bottle":
            col = {"rose": "bottle_red", "mango_sauce": "bottle_orange", "gula_melaka": "bottle_brown"}[s]
            b.cyl((0, 0, 0), 0.035, 0.035, 0.15, col, segs=6, caps=(True, False))
            b.cyl((0, 0, 0.15), 0.035, 0.012, 0.05, col, segs=6, caps=(False, False))
            b.cyl((0, 0, 0.2), 0.012, 0.012, 0.025, "white", segs=5)
        elif info["container"] == "can":
            b.cyl((0, 0, 0), 0.04, 0.04, 0.1, ("region", "can_" + s), segs=8, caps=(True, False))
            b.cyl((0, 0, 0.1), 0.04, 0.04, 0.005, "steel", segs=8, caps=(False, True))
            b.box((-0.006, 0.02, 0.105), (0.006, 0.03, 0.115), "steel_dark")     # punched hole
        else:
            b.box((-0.035, -0.035, 0), (0.035, 0.035, 0.12), "white",
                  faces={"front": ("region", "carton_" + s), "left": ("region", "carton_" + s),
                         "right": ("region", "carton_" + s)})
            b.frustum(0.12, 0.15, 0.07, 0.07, 0.07, 0.01, "white")
        ob = b.to_object("sauce_" + s)
        ob.location = (sx_, SAUCE_Y, z)
        objs.append(ob)

    # Soup pot on a burner at the right end of the bench, the ladle resting in it. The ladle is
    # its own object (origin = bottom of its cup) so the game can scoop and pour with it.
    b = Builder()
    px_, py_ = SOUP_POT
    b.box((px_ - 0.16, py_ - 0.16, z), (px_ + 0.16, py_ + 0.16, z + 0.07), "burner", skip=("bottom",))
    b.cyl((px_, py_, z + 0.07), 0.13, 0.14, 0.2, "steel", segs=10, caps=(False, False))
    b.cyl((px_, py_, z + 0.255), 0.14, 0.14, 0.015, "steel_dark", segs=10, caps=(False, False))
    b.cyl((px_, py_, z + 0.23), 0.135, 0.135, 0.001, "soup_yellow", segs=10)            # soup surface
    b.cyl((px_, py_, z + 0.231), 0.135, 0.14, 0.039, "steel", segs=10, caps=(False, False), inside=True)
    for sx in (-1, 1):                                                                  # handles
        b.box((px_ + sx * 0.14 - 0.02, py_ - 0.03, z + 0.22), (px_ + sx * 0.14 + 0.02, py_ + 0.03, z + 0.24),
              "steel_dark")
    objs.append(b.to_object("soup_pot", origin=(px_, py_, z)))
    marker("mk_pot", (px_, py_, z + 0.27))
    b = Builder()
    b.cyl((0, 0, 0), 0.025, 0.04, 0.03, "steel", segs=8, caps=(True, False))
    b.cyl((0, 0, 0.002), 0.025, 0.037, 0.028, "steel_dark", segs=8, caps=(False, False), inside=True)
    with b.at((0, 0.035, 0.025), rot_x=-35):
        b.box((-0.007, -0.007, 0), (0.007, 0.007, 0.3), "steel")
    ob = b.to_object("ladle")
    ob.location = (px_ - 0.04, py_ + 0.03, z + 0.2)
    objs.append(ob)
    return objs


def build_uncle():
    """Uncle: white singlet, specs, apron, towel on shoulder. Parts are separate so they can be
    animated in Godot (head nod, arm moves). Faces -Y (towards the customer).
    Stands in the open gap right of the display, behind the OPEN stand, so the waiting camera
    sees him from the waist up (behind the bench he was hidden by the display case)."""
    ux, uy = 0.82, 1.05
    root = bpy.data.objects.new("uncle", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (ux, uy, 0)

    b = Builder()
    with b.at((ux, uy, 0)):
        for sx in (-0.1, 0.1):
            b.box((sx - 0.07, -0.1, 0), (sx + 0.07, 0.07, 0.04), "slipper")
            b.box((sx - 0.05, -0.04, 0.04), (sx + 0.05, 0.05, 0.46), "skin")
        b.box((-0.19, -0.12, 0.44), (0.19, 0.12, 0.74), "shorts")
        with b.at((0, 0, 0)):
            b.frustum(0.72, 1.04, 0.42, 0.28, 0.46, 0.34, "singlet")        # round tummy
            b.frustum(1.04, 1.34, 0.46, 0.34, 0.42, 0.24, "singlet",
                      faces={"front": ("region", "singlet"), "top": "skin"})
        # apron over tummy and shorts
        b.box((-0.18, -0.19, 0.42), (0.18, -0.17, 1.02), "shorts", faces={"front": ("region", "apron")})
        b.box((-0.23, -0.15, 0.98), (0.23, 0.15, 1.01), "plastic_blue")
        # towel over left shoulder
        b.box((0.1, -0.14, 1.12), (0.2, -0.12, 1.35), "towel")
        b.box((0.1, -0.13, 1.34), (0.2, 0.13, 1.37), "towel")
        b.box((0.1, 0.12, 1.08), (0.2, 0.14, 1.35), "towel")
        b.cyl((0, 0, 1.33), 0.06, 0.06, 0.06, "skin", segs=6, caps=(False, False))
    body = b.to_object("uncle_body", origin=(ux, uy, 0), parent=root)

    b = Builder()
    hz = 1.38
    with b.at((ux, uy, hz)):
        b.frustum(0.0, 0.27, 0.25, 0.25, 0.23, 0.24, "skin",
                  faces={"front": ("region", "uncle_face"), "top": "hair", "back": ("region", "hair_back")})
        b.box((-0.145, -0.03, 0.1), (-0.125, 0.04, 0.16), "skin_dark")     # ears
        b.box((0.125, -0.03, 0.1), (0.145, 0.04, 0.16), "skin_dark")
        b.box((-0.13, -0.14, 0.17), (0.13, -0.125, 0.185), "specs")       # specs top bar
        b.box((-0.135, -0.13, 0.17), (-0.125, 0.02, 0.18), "specs")      # temple arms
        b.box((0.125, -0.13, 0.17), (0.135, 0.02, 0.18), "specs")
    b.to_object("uncle_head", origin=(ux, uy, hz), parent=root)

    for side, name in ((-1, "uncle_arm_r"), (1, "uncle_arm_l")):
        b = Builder()
        sx = ux + side * 0.27
        sz = 1.3
        with b.at((sx, uy, sz)):
            b.box((-0.055, -0.055, -0.3), (0.055, 0.055, 0.02), "skin")             # upper arm
            with b.at((0, 0, -0.3), rot_x=-35):
                b.box((-0.05, -0.05, -0.28), (0.05, 0.05, 0.0), "skin")           # forearm
                b.box((-0.045, -0.06, -0.37), (0.045, 0.04, -0.28), "skin_dark")  # hand
        b.to_object(name, origin=(sx, uy, sz), parent=root)
    return root


CUST_HIP = 0.8
CUST_NECK = 1.42


def build_customers():
    """Customer templates, parked far behind the stall (y 30) where no camera sees them; the game
    copies them. Each is an empty cust_<id> at the feet with parts cust_<id>_body/head/leg_l/leg_r.
    Leg origins are at the hip and the head origin at the neck, so Godot can swing and nod them.
    They face -Y, like the uncle (Godot: +Z)."""
    for i, (cid, p) in enumerate(CUSTOMERS.items()):
        build_customer(cid, p, (30.0 + i * 1.0, 30.0, 0.0))


def build_customer(cid, p, pos):
    s = p.get("scale", 1.0)
    pos = Vector(pos)
    root = bpy.data.objects.new("cust_" + cid, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = pos
    base = Matrix.Translation(pos) @ Matrix.Scale(s, 4)
    pivot = lambda local: pos + Vector(local) * s
    top, bottom, skin, hair = p["top"], p["bottom"], p["skin"], p["hair"]
    sleeve = p.get("sleeves", top)
    extra = p.get("extra", ())
    hip, neck = CUST_HIP, CUST_NECK

    b = Builder()
    b.push(base)
    if p["lower"] == "skirt":
        b.frustum(0.5, 0.9, 0.38, 0.26, 0.33, 0.21, bottom)
    else:
        b.box((-0.17, -0.1, 0.72), (0.17, 0.1, 0.9), bottom)
    b.frustum(0.88, neck, 0.34, 0.2, 0.38, 0.22, top,
              faces={"front": ("region", "cfront_" + cid)})
    b.cyl((0, 0, neck - 0.02), 0.05, 0.05, 0.06, skin, segs=6, caps=(False, False))
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.19, sx * 0.265))
        cuff = 0.86 if p.get("long") else 1.12
        b.box((lo, -0.055, cuff), (hi, 0.055, neck - 0.01), sleeve)
        if cuff > 0.9:
            b.box((lo + 0.006, -0.045, 0.86), (hi - 0.006, 0.045, cuff), skin)
        b.box((lo + 0.004, -0.05, 0.77), (hi - 0.004, 0.04, 0.86), p["skin"])          # hand
    if "backpack" in extra:
        b.box((-0.15, 0.11, 0.92), (0.15, 0.27, 1.34), "c_backpack")
        b.box((-0.11, 0.27, 0.98), (0.11, 0.3, 1.15), "c_navy")                    # front pocket
        for sx in (-0.11, 0.08):
            b.box((sx, -0.125, 1.1), (sx + 0.03, -0.11, neck - 0.01), "c_backpack")  # straps
    if "handbag" in extra:
        b.box((0.265, -0.07, 0.86), (0.33, 0.07, 1.04), "c_bag")
        b.box((0.27, -0.01, 1.04), (0.28, 0.01, 1.3), "c_bag")
    b.to_object("cust_%s_body" % cid, origin=pos, parent=root)

    b = Builder()
    b.push(base)
    with b.at((0, 0, neck + 0.02)):
        b.frustum(0.0, 0.24, 0.22, 0.22, 0.21, 0.21, skin,
                  faces={"front": ("region", "cface_" + cid), "top": hair, "back": hair})
        b.box((-0.125, -0.02, 0.08), (-0.105, 0.04, 0.14), _shade_name(skin))      # ears
        b.box((0.105, -0.02, 0.08), (0.125, 0.04, 0.14), _shade_name(skin))
        style = p["hair_style"]
        if style == "hardhat":
            b.cyl((0, 0, 0.19), 0.135, 0.1, 0.1, "c_hardhat", segs=8)
            b.box((-0.145, -0.18, 0.18), (0.145, 0.15, 0.205), "c_hardhat")      # brim
        elif style == "perm":
            b.box((-0.135, -0.12, 0.16), (0.135, 0.14, 0.31), hair)
            for sx in (-1, 1):
                lo, hi = sorted((sx * 0.108, sx * 0.135))
                b.box((lo, -0.07, 0.05), (hi, 0.14, 0.17), hair)
            b.box((-0.135, 0.11, 0.03), (0.135, 0.14, 0.17), hair)
        else:
            b.box((-0.115, -0.115, 0.2), (0.115, 0.115, 0.265), hair)
            b.box((-0.115, 0.1, 0.06 if style == "short" else 0.0), (0.115, 0.122, 0.22), hair)
            if style == "bun":
                b.box((-0.05, 0.1, 0.2), (0.05, 0.19, 0.3), hair)
            elif style == "ponytail":
                b.box((-0.035, 0.12, -0.02), (0.035, 0.175, 0.24), hair)
                b.box((-0.04, 0.115, 0.2), (0.04, 0.17, 0.235), "c_backpack")     # hair tie
    b.to_object("cust_%s_head" % cid, origin=pivot((0, 0, neck)), parent=root)

    for side, nm in ((-1, "leg_r"), (1, "leg_l")):
        b = Builder()
        b.push(base)
        lx = side * 0.085
        with b.at((lx, 0, 0)):
            if p["lower"] == "pants":
                b.box((-0.062, -0.062, 0.06), (0.062, 0.062, hip), bottom)
            elif p["lower"] == "shorts":
                b.box((-0.066, -0.066, 0.52), (0.066, 0.066, hip), bottom)
                b.box((-0.048, -0.048, 0.06), (0.048, 0.048, 0.52), skin)
            else:   # skirt hides the top of the leg
                b.box((-0.045, -0.045, 0.06), (0.045, 0.045, 0.62), skin)
            if p["shoes"] == "slipper":
                b.box((-0.06, -0.13, 0.0), (0.06, 0.06, 0.025), "slipper")
                b.box((-0.045, -0.11, 0.025), (0.045, 0.045, 0.06), skin)
            else:
                b.box((-0.06, -0.13, 0.0), (0.06, 0.065, 0.075), p["shoes"])
        b.to_object("cust_%s_%s" % (cid, nm), origin=pivot((lx, 0, hip)), parent=root)


def _shade_name(skin):
    """Ears: the next darker customer skin swatch (or uncle's skin_dark for the darkest)."""
    return {"c_skin_lt": "c_skin_md", "c_skin_md": "c_skin_dk"}.get(skin, "skin_dark")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)

    paint_signboard()
    paint_menu_lightbox()
    paint_neighbours()
    paint_props()
    paint_floor_and_walls()
    paint_customers()
    atlas.save(os.path.join(TEX_DIR, "atlas.png"))

    b = Builder()
    build_hall(b)
    build_lights(b)
    for x in (-UNIT_W * 1.5, -UNIT_W / 2, UNIT_W / 2, UNIT_W * 1.5):
        build_partition(b, x)
    build_partition(b, -UNIT_W * 2.5)
    build_partition(b, UNIT_W * 2.5)
    build_our_stall(b)
    build_left_neighbour(b)
    build_right_neighbour(b)
    build_far_units(b)
    # glass panels are their own object (transparent, no shadow)
    static = b.to_object("static")

    g = Builder()
    dx0, dx1, dy0, dy1 = -1.95, 0.45, 0.12, 0.92
    g.box((dx0, dy0, 0.82), (dx1, dy1, 1.3), "glass_frame", mat="glass", skip=("bottom",))
    g.to_object("glass")

    r = Builder()
    build_roof(r)
    r.to_object("roof")

    build_fan("fan_1", (-2.6, -3.0, 3.35))
    build_fan("fan_2", (3.0, -6.5, 3.35))
    build_props()
    build_uncle()
    build_customers()
    for view, (pos, target, _fov) in CAMERAS.items():
        marker("cam_" + view, pos)
        marker("cam_%s_target" % view, target)

    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_yup=True,
                              export_apply=False, export_materials="EXPORT", export_cameras=False,
                              export_lights=False)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("BUILD_OK objects=%d tris=%d" % (len([o for o in bpy.data.objects if o.type == "MESH"]), tris))
    if "--preview" in sys.argv:
        render_previews()


def render_previews():
    """Rough layout check without opening Godot: Workbench renders of each camera view at the
    game's 480x270, flat atlas colours, to build/preview_<view>.png. Not the game's lighting."""
    imgs = {}
    for name, path in (("atlas", "atlas.png"), ("glow", "atlas.png"), ("floor", "floor.png"),
                       ("walltile", "walltile.png")):
        img = imgs.get(path) or bpy.data.images.load(os.path.join(TEX_DIR, path))
        imgs[path] = img
        m = bpy.data.materials.get(name)
        if m is None:
            continue
        m.use_nodes = True
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Closest"
        nt.nodes.active = tex
        if name in ("floor", "walltile"):     # repeat textures use world-scaled UVs already
            tex.extension = "REPEAT"
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.render.resolution_x, sc.render.resolution_y = 480, 270
    sc.render.resolution_percentage = 200
    cam_data = bpy.data.cameras.new("preview")
    cam_data.sensor_fit = "VERTICAL"
    cam = bpy.data.objects.new("preview", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # plus a lineup of the customer templates (parked at y 30, front faces -Y)
    lineup = {"customers": ((33.5, 22.0, 1.0), (33.5, 30.0, 0.85), 30)}
    for view, (pos, target, fov) in {**CAMERAS, **lineup}.items():
        cam_data.angle_y = math.radians(fov)
        cam.location = pos
        cam.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(ROOT, "build", "preview_%s.png" % view)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath)


main()
