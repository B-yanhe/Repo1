/*
 * make-icon.js — build the Windows .ico used by the desktop shortcut.
 *
 * Two source kinds are supported:
 *   .svg  the harness whale mark, drawn white on a rounded DeepSeek-blue tile
 *   raster (png/jpg/webp)  an illustration, cover-cropped to a rounded square
 *
 * Both emit 16/24/32/48/64/128 BMP entries plus one 256 PNG entry — the layout
 * Windows Explorer expects.
 *
 * Usage:
 *   node make-icon.js <sharpPackageDir> <source.(svg|png)> <out.ico>
 */

const fs = require('fs');

const [sharpDir, sourcePath, outPath] = process.argv.slice(2);
if (!sharpDir || !sourcePath || !outPath) {
  console.error('usage: node make-icon.js <sharpPackageDir> <source.(svg|png)> <out.ico>');
  process.exit(2);
}
const sharp = require(sharpDir);

const BMP_SIZES = [16, 24, 32, 48, 64, 128];
const PNG_SIZE = 256;
const TILE_COLOR = '#4D6BFE'; // DeepSeek blue
const TILE_RADIUS_RATIO = 0.22;
const INSET_RATIO = 0.17;

/** Rounded-rectangle alpha mask that turns a square crop into an app tile. */
function roundedMask(size) {
  const radius = Math.round(size * TILE_RADIUS_RATIO);
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      `<rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="#FFFFFF"/>` +
      `</svg>`,
  );
}

/** Read the whale glyph and force it to solid white (the SVG defaults to black). */
function whiteWhaleSource() {
  const svg = fs.readFileSync(sourcePath, 'utf8');
  return Buffer.from(
    svg
      .replace(/<style>[\s\S]*?<\/style>/u, '') // drop the prefers-color-scheme override
      .replace(/fill="#000"/gu, 'fill="#FFFFFF"'),
  );
}

/** SVG source: rounded blue tile with the centered white whale. */
async function renderLogo(size) {
  const radius = Math.round(size * TILE_RADIUS_RATIO);
  const background = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      `<rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="${TILE_COLOR}"/>` +
      `</svg>`,
  );
  const inset = Math.max(0, Math.round(size * INSET_RATIO));
  const inner = size - inset * 2;
  const whale = await sharp(whiteWhaleSource(), { density: 1024 })
    .resize(inner, inner, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
  return sharp(background)
    .composite([{ input: whale, top: inset, left: inset }])
    .png()
    .toBuffer();
}

/** Raster source: cover-cropped to a square, then rounded off at the corners. */
async function renderArt(size) {
  const square = await sharp(sourcePath)
    .resize(size, size, { fit: 'cover', position: 'centre' })
    .png()
    .toBuffer();
  return sharp(square)
    .composite([{ input: roundedMask(size), blend: 'dest-in' }])
    .png()
    .toBuffer();
}

const renderTile = /\.svg$/iu.test(sourcePath) ? renderLogo : renderArt;

/** Build one classic 32-bit BMP icon entry (BITMAPINFOHEADER + XOR + AND mask). */
function bmpEntry(size, rgba) {
  const header = Buffer.alloc(40);
  header.writeUInt32LE(40, 0); // biSize
  header.writeInt32LE(size, 4); // biWidth
  header.writeInt32LE(size * 2, 8); // biHeight (XOR + AND)
  header.writeUInt16LE(1, 12); // biPlanes
  header.writeUInt16LE(32, 14); // biBitCount
  header.writeUInt32LE(0, 16); // BI_RGB
  header.writeUInt32LE(size * size * 4, 20); // biSizeImage

  const pixels = Buffer.alloc(size * size * 4); // bottom-up BGRA
  for (let y = 0; y < size; y += 1) {
    const sourceRow = (size - 1 - y) * size * 4;
    for (let x = 0; x < size; x += 1) {
      const s = sourceRow + x * 4;
      const d = (y * size + x) * 4;
      pixels[d] = rgba[s + 2];
      pixels[d + 1] = rgba[s + 1];
      pixels[d + 2] = rgba[s];
      pixels[d + 3] = rgba[s + 3];
    }
  }

  const maskStride = Math.ceil(size / 32) * 4;
  const mask = Buffer.alloc(maskStride * size); // fully opaque => zeroed mask
  return Buffer.concat([header, pixels, mask]);
}

async function main() {
  const images = [];
  for (const size of BMP_SIZES) {
    const png = await renderTile(size);
    const { data } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    images.push({ size, data: bmpEntry(size, data) });
  }
  images.push({ size: PNG_SIZE, data: await renderTile(PNG_SIZE) });

  const directory = Buffer.alloc(6);
  directory.writeUInt16LE(0, 0); // reserved
  directory.writeUInt16LE(1, 2); // type: icon
  directory.writeUInt16LE(images.length, 4);

  const entries = [];
  let offset = 6 + images.length * 16;
  for (const image of images) {
    const entry = Buffer.alloc(16);
    entry.writeUInt8(image.size >= 256 ? 0 : image.size, 0); // 0 means 256
    entry.writeUInt8(image.size >= 256 ? 0 : image.size, 1);
    entry.writeUInt8(0, 2); // palette count
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(image.data.length, 8);
    entry.writeUInt32LE(offset, 12);
    entries.push(entry);
    offset += image.data.length;
  }

  fs.writeFileSync(outPath, Buffer.concat([directory, ...entries, ...images.map((i) => i.data)]));
  console.log(`wrote ${outPath} (${images.length} entries, ${fs.statSync(outPath).size} bytes)`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
