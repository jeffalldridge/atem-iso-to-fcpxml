#!/usr/bin/env python3
"""Convert a flattened 2x window capture to an RGBA PNG (requires Pillow).

Only the outside corner matte is masked. Captured UI pixels are not resized or
redrawn. For genuine alpha-channel source captures, use those PNGs directly.
"""
import argparse
from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('output')
    args = parser.parse_args()
    image = Image.open(args.source).convert('RGBA')
    width, height = image.size
    scale = 4
    # Source-pixel geometry of these macOS window captures, not a CSS radius.
    inset, corner = 2, 40
    points = [(corner, inset), (width-corner, inset)]
    curves = [((width-corner, inset), (width-inset, inset), (width-inset, corner)),
              ((width-inset, height-corner), (width-inset, height-inset), (width-corner, height-inset)),
              ((corner, height-inset), (inset, height-inset), (inset, height-corner)),
              ((inset, corner), (inset, inset), (corner, inset))]
    for start, control, end in curves:
        points.append(start)
        for step in range(1, 65):
            t = step / 64
            points.append(tuple((1-t)**2 * start[i] + 2*(1-t)*t*control[i] + t*t*end[i] for i in (0, 1)))
    mask = Image.new('L', (width*scale, height*scale))
    ImageDraw.Draw(mask).polygon([(round(x*scale), round(y*scale)) for x, y in points], fill=255)
    image.putalpha(mask.resize(image.size, Image.Resampling.LANCZOS))
    image.save(args.output, optimize=True)


if __name__ == '__main__':
    main()
