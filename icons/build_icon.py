from PIL import Image, ImageDraw

CANVAS = 1024
BG_COLOR = "#1C1E22"       # dark charcoal
ACCENT_COLOR = "#D9A441"   # warm brass/gold

img = Image.new("RGB", (CANVAS, CANVAS), BG_COLOR)
draw = ImageDraw.Draw(img)

center_x = CANVAS // 2

# Constant-thickness "staple" construction: an outer rounded shape (two
# straight tines + a semicircular U-turn at the bottom) with a same-shaped
# but narrower cutout removed from the top down partway, leaving a solid
# band of even thickness tracing the outline — this is how a real
# tuning fork's silhouette actually reads, unlike v1/v2's "block with a
# slot," which read as a paddle/shield instead of two distinct tines.

fork_width = 320       # outer envelope: both tines + the gap between them
tine_thickness = 85    # material thickness of each tine
top_y = 180
outer_bottom_y = 620   # bottom of the semicircular U-turn

fork_left = center_x - fork_width // 2
fork_right = center_x + fork_width // 2
outer_radius = fork_width // 2  # == width/2 -> bottom corners meet as a clean semicircle

# 1. Outer shape: straight sides + semicircular bottom
draw.rounded_rectangle(
    [fork_left, top_y, fork_right, outer_bottom_y],
    radius=outer_radius,
    corners=(False, False, True, True),
    fill=ACCENT_COLOR,
)

# 2. Inner cutout: same construction, inset by the tine thickness on each
#    side, stopping short of the outer bottom so the U-turn stays solid.
inner_left = fork_left + tine_thickness
inner_right = fork_right - tine_thickness
inner_bottom_y = outer_bottom_y - tine_thickness
inner_radius = (inner_right - inner_left) // 2

draw.rounded_rectangle(
    [inner_left, top_y, inner_right, inner_bottom_y],
    radius=inner_radius,
    corners=(False, False, True, True),
    fill=BG_COLOR,
)

# 3. Round off the two tine tops to match the curve's roundedness
tip_radius = tine_thickness // 2
draw.rounded_rectangle(
    [fork_left, top_y, fork_left + tine_thickness, top_y + tine_thickness],
    radius=tip_radius,
    corners=(True, False, False, False),
    fill=ACCENT_COLOR,
)
draw.rectangle([fork_left, top_y + tip_radius, fork_left + tine_thickness, top_y + tine_thickness], fill=ACCENT_COLOR)
draw.rounded_rectangle(
    [fork_right - tine_thickness, top_y, fork_right, top_y + tine_thickness],
    radius=tip_radius,
    corners=(False, True, False, False),
    fill=ACCENT_COLOR,
)

# 4. Stem, overlapping up into the U-turn so there's no seam. Ends in a
#    solid notehead instead of a rounded cap — same continuous shape, but
#    it reads as "a musical note whose flag is a tuning fork": a fork and
#    a note are already structurally similar (both a stem with something
#    distinctive at one end), so this fuses them without adding a second
#    competing shape or hurting small-size legibility.
stem_width = 70
stem_left = center_x - stem_width // 2
stem_right = center_x + stem_width // 2
stem_top_y = outer_bottom_y - 60
notehead_center_y = 760
notehead_radius = 95

draw.rectangle([stem_left, stem_top_y, stem_right, notehead_center_y], fill=ACCENT_COLOR)
draw.ellipse(
    [
        center_x - notehead_radius,
        notehead_center_y - notehead_radius,
        center_x + notehead_radius,
        notehead_center_y + notehead_radius,
    ],
    fill=ACCENT_COLOR,
)

img.save("icons/icon_draft_v4_note.png")
print("Saved icons/icon_draft_v4_note.png", img.size)

small = img.resize((120, 120), Image.LANCZOS)
small.save("icons/icon_draft_v4_note_small.png")
print("Saved icons/icon_draft_v4_note_small.png", small.size)

tiny = img.resize((58, 58), Image.LANCZOS)
tiny.save("icons/icon_draft_v4_note_tiny58.png")
print("Saved icons/icon_draft_v4_note_tiny58.png", tiny.size)
