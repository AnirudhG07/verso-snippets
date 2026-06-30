#!/usr/bin/env python3
# decode-link.py — print the Lean source behind a live.lean-lang.org share link
# (or read stdin with `-`). Used internally by `lean-snippet link=…`; not meant
# to be called directly.
#
# Handles the editor's three share formats in the URL fragment:
#   #code=…   plain, percent-encoded   (what our own "Try it!" button emits)
#   #codez=…  LZ-string compressed
#   #url=…    a URL the editor loads the code from

import os, re, sys, urllib.parse, urllib.request

# ── vendored LZ-string decoder (decompressFromEncodedURIComponent), no deps ────
_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"

def _decompress(length, reset_value, get_next):
    dictionary = {0: 0, 1: 1, 2: 2}
    enlarge_in, dict_size, num_bits = 4, 4, 3
    result = []
    val = get_next(0); position = reset_value; index = 1

    def read(maxpower):
        nonlocal val, position, index
        bits, power = 0, 1
        while power != maxpower:
            resb = val & position; position >>= 1
            if position == 0:
                position = reset_value; val = get_next(index); index += 1
            bits |= (1 if resb > 0 else 0) * power; power <<= 1
        return bits

    nxt = read(1 << 2)
    if nxt == 2:
        return ""
    c = chr(read(1 << (8 if nxt == 0 else 16)))
    dictionary[3] = c; w = c; result.append(c)
    while True:
        if index > length:
            return ""
        c = read(1 << num_bits)
        if c in (0, 1):
            dictionary[dict_size] = chr(read(1 << (8 if c == 0 else 16)))
            dict_size += 1; c = dict_size - 1; enlarge_in -= 1
        elif c == 2:
            return "".join(result)
        if enlarge_in == 0:
            enlarge_in = 1 << num_bits; num_bits += 1
        if c in dictionary:
            entry = dictionary[c]
        elif c == dict_size:
            entry = w + w[0]
        else:
            return None
        result.append(entry)
        dictionary[dict_size] = w + entry[0]; dict_size += 1; enlarge_in -= 1
        w = entry
        if enlarge_in == 0:
            enlarge_in = 1 << num_bits; num_bits += 1

def decompress_codez(s):
    s = s.replace(" ", "+")
    return _decompress(len(s), 32, lambda i: _KEY.index(s[i]))

def code_from_url(u):
    frag = u.split("#", 1)[1] if "#" in u else u.split("?", 1)[-1]
    parts = {}
    for kv in frag.split("&"):
        if "=" in kv:
            k, v = kv.split("=", 1); parts[k] = v
    if "url" in parts:
        return urllib.request.urlopen(urllib.parse.unquote(parts["url"])).read().decode("utf-8")
    if "code" in parts:
        return urllib.parse.unquote(parts["code"])
    if "codez" in parts:
        return decompress_codez(parts["codez"])
    sys.exit("decode-link: no #code= / #codez= / #url= found in the URL")

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "-"
    if src == "-":
        code = sys.stdin.read()
    elif re.match(r"https?://", src):
        code = code_from_url(src)
    else:
        code = open(src, encoding="utf-8").read()
    if re.search(r"^\s*import\s+Mathlib", code, re.M):
        print("lean-snippet: note — this code imports Mathlib; this repo ships Std "
              "only. Add Mathlib as a dependency (see the README) or it won't build.",
              file=sys.stderr)
    sys.stdout.write(code)

if __name__ == "__main__":
    main()
