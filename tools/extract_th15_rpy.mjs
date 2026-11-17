#!/usr/bin/env node
// Extract the playable frame-input stream from a TH15 replay.
// Output is a Lua table used by play_th15_replay.lua; no game files are modified.
import fs from "node:fs/promises";
import path from "node:path";

const input = process.argv[2];
const output = process.argv[3] || input?.replace(/\.rpy$/i, ".lua");
const requestedStage = process.argv[4] === undefined ? null : Number(process.argv[4]);
if (!input || !output) {
  console.error("Usage: node tools/extract_th15_rpy.mjs <replay.rpy> [output.lua] [stage 1-6]");
  process.exit(2);
}
if (requestedStage !== null && (!Number.isInteger(requestedStage) || requestedStage < 1 || requestedStage > 6)) {
  throw new Error(`Invalid requested stage ${requestedStage}; expected 1-6`);
}

const bytes = new Uint8Array(await fs.readFile(input));
const u32 = (b, p) => (b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)) >>> 0;
const i32 = (b, p) => u32(b, p) | 0;
const u16 = (b, p) => b[p] | (b[p + 1] << 8);
if (String.fromCharCode(...bytes.slice(0, 4)) !== "t15r") throw new Error("Not a TH15 replay (expected t15r)");
const compressedLength = u32(bytes, 28);
const decodedLength = u32(bytes, 32);
if (compressedLength > bytes.length - 36 || decodedLength > 64 * 1024 * 1024) throw new Error("Invalid replay body sizes");

function xorBlockDecode(buf, length, blockSize, base, add) {
  const source = buf.slice(0, length);
  let p = 0, left = length;
  if (left % blockSize < blockSize / 4) left -= left % blockSize;
  left -= length & 1;
  while (left) {
    if (left < blockSize) blockSize = left;
    const blockStart = p;
    let tp = p + blockSize - 1;
    for (let i = 0; i < (blockSize + (blockSize & 1)) / 2; i++, p++) {
      buf[tp] = source[p] ^ base; base = (base + add) & 255; tp -= 2;
    }
    tp = blockStart + blockSize - 2;
    for (let i = 0; i < blockSize / 2; i++, p++) {
      buf[tp] = source[p] ^ base; base = (base + add) & 255; tp -= 2;
    }
    left -= blockSize;
  }
}

const compressed = bytes.slice(36, 36 + compressedLength);
xorBlockDecode(compressed, compressedLength, 0x400, 0x5c, 0xe1);
xorBlockDecode(compressed, compressedLength, 0x100, 0x7d, 0x3a);
const body = new Uint8Array(decodedLength), dict = new Uint8Array(0x2010);
let src = 0, filter = 0x80, dst = 0;
function readBits(n) {
  let out = 0;
  for (let i = 0; i < n; i++) {
    out <<= 1;
    if (src < compressedLength && (compressed[src] & filter)) out |= 1;
    filter >>= 1;
    if (!filter) { src++; filter = 0x80; }
  }
  return out >>> 0;
}
while (src < compressedLength && dst < decodedLength) {
  if (src >= compressedLength) break;
  if (readBits(1)) {
    if (src >= compressedLength) break;
    const value = readBits(8);
    if (dst >= decodedLength) break;
    body[dst] = value; dict[dst & 0x1fff] = value; dst++;
  } else {
    if (src >= compressedLength) break;
    const from = readBits(13) - 1;
    if (src >= compressedLength) break;
    const count = readBits(4) + 3;
    for (let i = 0; i < count && dst < decodedLength; i++) {
      const value = dict[(from + i) & 0x1fff];
      dict[dst & 0x1fff] = value; body[dst++] = value;
    }
  }
}
if (dst !== decodedLength) throw new Error(`Replay decompression stopped at ${dst}/${decodedLength} bytes`);

const stageCount = Math.min(body[0x88] || 0, 6);
if (!stageCount) throw new Error("Replay contains no stage records");
let stageOffset = 0xa4, stageData = null;
for (let i = 0; i < stageCount; i++) {
  const inputOffset = stageOffset + 0x238;
  if (inputOffset > body.length) throw new Error("Truncated TH15 stage header");
  const id = u16(body, stageOffset);
  const frames = u32(body, stageOffset + 4);
  const dataLength = u32(body, stageOffset + 8);
  if (inputOffset + dataLength > body.length) throw new Error(`Truncated TH15 stage ${id} data`);
  if (id >= 1 && id <= 6 && (requestedStage === null || id === requestedStage)) {
    // 45d13c restores the seed and globals. 45b510 reads the fixed-point start position.
    stageData = { id, frames, offset: inputOffset,
      seed: u16(body, stageOffset + 2),
      x: i32(body, stageOffset + 0x0c) / 128,
      y: i32(body, stageOffset + 0x10) / 128,
      character: u32(body, stageOffset + 0x28),
      difficulty: u32(body, stageOffset + 0x34),
      graze: u32(body, stageOffset + 0x40),
      power: u32(body, stageOffset + 0x64) / 100,
      lives: i32(body, stageOffset + 0x74), bombs: i32(body, stageOffset + 0x80),
      pointRate: u32(body, stageOffset + 0x58) / 100 };
  }
  if (frames * 6 > dataLength || dataLength - frames * 6 !== Math.ceil(frames / 30)) {
    throw new Error(`Unexpected TH15 stage data layout at stage ${id}: frames=${frames}, bytes=${dataLength}`);
  }
  stageOffset += dataLength + 0x238;
}
if (!stageData) throw new Error(`Replay stage record was not found${requestedStage ? ` for stage ${requestedStage}` : ""}`);

const { character, difficulty } = stageData;
const characterKey = ["reimu", "marisa", "sanae", "reisen"][character];
const difficultyName = ["Easy", "Normal", "Hard", "Lunatic"][difficulty];
if (!characterKey || !difficultyName) throw new Error(`Unsupported replay metadata: ${character} / ${difficulty}`);

const controls = [];
let previous = -1;
for (let frame = 0; frame < stageData.frames; frame++) {
  const p = stageData.offset + frame * 6;
  let held = u16(body, p);
  // The final all-ones record is the replay terminator, not a direction to hold.
  if (held === 0xffff) held = 0;
  if (held !== previous) { controls.push([frame + 1, held]); previous = held; }
}
const lua = [
  "-- Generated from an original TH15 replay. Input masks are held states.",
  "return {",
  `  source = ${JSON.stringify(path.basename(input))}, stage = ${stageData.id}, frames = ${stageData.frames},`,
  `  character = ${JSON.stringify(characterKey)}, difficulty = ${difficulty},`,
  `  seed = ${stageData.seed}, start_x = ${stageData.x}, start_y = ${stageData.y},`,
  `  power = ${stageData.power}, lives = ${stageData.lives}, bombs = ${stageData.bombs}, point_rate = ${stageData.pointRate}, graze = ${stageData.graze},`,
  "  controls = {",
  ...controls.map(([frame, mask]) => `    {${frame}, ${mask}},`),
  "  },",
  "}",
  "",
].join("\n");
await fs.writeFile(output, lua, "utf8");
console.log(`${path.basename(input)}: stage ${stageData.id}, ${stageData.frames} frames, ${characterKey} / ${difficultyName}, seed ${stageData.seed}, ${controls.length} input changes`);
console.log(`Wrote ${output}`);
