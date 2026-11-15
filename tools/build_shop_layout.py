"""Writes src/SoloShop/gui/layouts/shop.layout from the description below.

Every position and size is a fraction of the parent widget, so the shop fills the screen
and keeps its proportions at any resolution or UI scale. Text is sized from script.
"""
from pathlib import Path

GRID_COLUMNS = 5
GRID_ROWS = 3
GRID_X, GRID_Y, GRID_W, GRID_H = 0.015, 0.15, 0.97, 0.75
CARD_GAP_X, CARD_GAP_Y = 0.012, 0.015
CARD_W = (GRID_W - CARD_GAP_X * (GRID_COLUMNS - 1)) / GRID_COLUMNS
CARD_H = (GRID_H - CARD_GAP_Y * (GRID_ROWS - 1)) / GRID_ROWS

WINDOW = "0.045 0.05 0.05 0.97"
BAR = "0.085 0.095 0.095 1"
PANEL = "0.065 0.075 0.075 1"
CARD = "0.1 0.11 0.11 1"
CARD_EDGE = "0.16 0.17 0.17 1"
FIELD = "0.03 0.035 0.035 1"
NAV = "0.12 0.13 0.13 1"
GREEN = "0.28 0.62 0.3 1"
BUY = "0.26 0.5 0.27 1"
SELL = "0.55 0.2 0.18 1"
CLOSE = "0.45 0.16 0.14 1"
WHITE = "1 1 1 1"
MUTED = "0.66 0.68 0.66 1"
GOLD = "1 0.82 0.4 1"
MONEY = "0.45 0.9 0.45 1"
FONT = "gui/fonts/metron"
FONT_BIG = "gui/fonts/metron28"


def box(x, y, w, h, extra=None):
    props = [("position", f"{x:.4f} {y:.4f}"), ("size", f"{w:.4f} {h:.4f}"),
             ("hexactpos", 0), ("vexactpos", 0), ("hexactsize", 0), ("vexactsize", 0)]
    return props + (extra or [])


def panel(name, x, y, w, h, color, children=None, extra=None):
    props = box(x, y, w, h, [("color", color), ("style", "rover_sim_colorable")] + (extra or []))
    return ("PanelWidgetClass", name, props, children or [])


def text(name, x, y, w, h, value, font=FONT, color=WHITE, extra=None):
    props = box(x, y, w, h, [("ignorepointer", 1), ("color", color), ("text", f'"{value}"'), ("font", f'"{font}"')] + (extra or []))
    return ("TextWidgetClass", name, props, [])


def label(name, x, y, w, h, value, font=FONT_BIG):
    """A click-through text label; the menu script centres it inside its box."""
    return text(name, x, y, w, h, value, font, WHITE)


def button(name, x, y, w, h, value, back_color, font=FONT_BIG):
    """Coloured back panel, centred text label, and an invisible click area on top.

    A button's colour also tints its own text, so the visible text lives in a separate label.
    """
    back = panel(f"{name}Back", x, y, w, h, back_color, extra=[("ignorepointer", 1)])
    caption = label(f"{name}Label", x, y, w, h, value, font)
    click = ("ButtonWidgetClass", name, box(x, y, w, h, [("color", "1 1 1 0")]), [])
    return [back, caption, click]


def card(index):
    column, row = index % GRID_COLUMNS, index // GRID_COLUMNS
    x = GRID_X + column * (CARD_W + CARD_GAP_X)
    y = GRID_Y + row * (CARD_H + CARD_GAP_Y)
    name = f"Card{index}"
    return panel(name, x, y, CARD_W, CARD_H, CARD_EDGE, [
        panel(f"{name}Back", 0.02, 0.02, 0.96, 0.96, CARD, extra=[("ignorepointer", 1)]),
        panel(f"{name}Owned", 0.06, 0.05, 0.07, 0.07, GREEN, extra=[("ignorepointer", 1)]),
        ("ItemPreviewWidgetClass", f"{name}Preview", box(0.08, 0.06, 0.84, 0.55, [("ignorepointer", 1)]), []),
        text(f"{name}Name", 0.06, 0.63, 0.88, 0.18, "", FONT, WHITE, [("wrap", 1)]),
        text(f"{name}Price", 0.06, 0.82, 0.88, 0.13, "", FONT, GOLD),
        ("ButtonWidgetClass", f"{name}Button", box(0, 0, 1, 1, [("color", "1 1 1 0")]), []),
    ])


header = panel("Header", 0, 0, 1, 0.085, BAR, [
    text("PlayerName", 0.015, 0.1, 0.3, 0.42, "Survivor", FONT_BIG, WHITE),
    text("TraderName", 0.015, 0.54, 0.3, 0.34, "Solo Trader", FONT, MUTED),
    text("Balance", 0.32, 0.26, 0.24, 0.48, "MONEY: $0", FONT_BIG, MONEY),
    text("CashHint", 0.565, 0.3, 0.07, 0.4, "CASH $", FONT, MUTED),
    panel("CashAmountBack", 0.635, 0.2, 0.09, 0.6, FIELD, [
        ("EditBoxWidgetClass", "CashAmount", box(0.06, 0.12, 0.88, 0.76, [("font", f'"{FONT}"'), ("color", WHITE)]), []),
    ]),
    *button("CashOut", 0.73, 0.18, 0.095, 0.64, "CASH OUT", BUY, FONT),
    *button("PayIn", 0.83, 0.18, 0.125, 0.64, "PAY IN ALL CASH", NAV, FONT),
    *button("Close", 0.965, 0.18, 0.025, 0.64, "X", CLOSE),
])

sidebar = panel("Sidebar", 0, 0.09, 0.09, 0.91, BAR, [
    *button("NavMarket", 0.07, 0.02, 0.86, 0.075, "MARKET", NAV, FONT),
    *button("NavInventory", 0.07, 0.105, 0.86, 0.075, "INVENTORY", NAV, FONT),
    *button("NavVehicles", 0.07, 0.19, 0.86, 0.075, "VEHICLES", NAV, FONT),
])

center = panel("Center", 0.098, 0.09, 0.572, 0.895, PANEL, [
    panel("SearchBack", 0.015, 0.015, 0.34, 0.05, FIELD, [
        ("EditBoxWidgetClass", "Search", box(0.03, 0.1, 0.94, 0.8, [("font", f'"{FONT}"'), ("color", WHITE)]), []),
    ]),
    text("SearchHint", 0.37, 0.025, 0.3, 0.035, "Search", FONT, MUTED),
    panel("CategoryBar", 0.015, 0.08, 0.97, 0.055, BAR, [
        *button("CategoryPrev", 0, 0, 0.06, 1, "<", NAV),
        label("CategoryName", 0.06, 0, 0.88, 1, "ALL"),
        *button("CategoryNext", 0.94, 0, 0.06, 1, ">", NAV),
    ]),
    *[card(i) for i in range(GRID_COLUMNS * GRID_ROWS)],
    *button("PagePrev", 0.36, 0.915, 0.06, 0.055, "<", NAV),
    label("PageText", 0.43, 0.915, 0.14, 0.055, "1 / 1"),
    *button("PageNext", 0.58, 0.915, 0.06, 0.055, ">", NAV),
])

detail = panel("Detail", 0.68, 0.09, 0.31, 0.895, PANEL, [
    label("DetailTitle", 0, 0.01, 1, 0.05, "PRODUCT INFORMATION"),
    ("ItemPreviewWidgetClass", "Preview", box(0.06, 0.08, 0.88, 0.4), []),
    text("ItemName", 0.06, 0.5, 0.88, 0.07, "Pick an item", FONT_BIG, WHITE, [("wrap", 1)]),
    text("Owned", 0.06, 0.575, 0.88, 0.04, "", FONT, MUTED),
    text("QuantityLabel", 0.06, 0.648, 0.4, 0.04, "QUANTITY", FONT, MUTED),
    *button("Minus", 0.5, 0.635, 0.1, 0.06, "<", NAV),
    label("Quantity", 0.61, 0.635, 0.12, 0.06, "1"),
    *button("Plus", 0.74, 0.635, 0.1, 0.06, ">", NAV),
    *button("Buy", 0.06, 0.73, 0.42, 0.085, "BUY", BUY),
    *button("Sell", 0.52, 0.73, 0.42, 0.085, "SELL", SELL),
    text("Status", 0.06, 0.84, 0.88, 0.12, "", FONT, MUTED, [("wrap", 1)]),
])

root = ("FrameWidgetClass", "SoloShopRoot", box(0, 0, 1, 1), [
    panel("Window", 0, 0, 1, 1, WINDOW, [header, sidebar, center, detail]),
])


def render(node, indent=0):
    cls, name, props, children = node
    pad = " " * indent
    lines = [f"{pad}{cls} {name} {{"]
    for key, value in props:
        lines.append(f"{pad} {key} {value}")
    if children:
        lines.append(f"{pad} {{")
        for child in children:
            lines.extend(render(child, indent + 2))
        lines.append(f"{pad} }}")
    lines.append(f"{pad}}}")
    return lines


out = Path(__file__).resolve().parent.parent / "src" / "SoloShop" / "gui" / "layouts" / "shop.layout"
out.write_text("\n".join(render(root)) + "\n")
print(f"Wrote {out}")
