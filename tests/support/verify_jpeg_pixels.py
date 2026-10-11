"""Optional native verification; Pillow is a development-only dependency."""
import sys
from PIL import Image

with Image.open(sys.argv[1]) as before, Image.open(sys.argv[2]) as after:
    before.load()
    after.load()
    assert before.size == after.size, "Image dimensions changed"
    assert before.convert("RGB").tobytes() == after.convert("RGB").tobytes(), "Decoded pixels changed"
