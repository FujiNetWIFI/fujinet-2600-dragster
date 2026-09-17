#!/usr/bin/env python3
"""strip.py -- reduce an AS source to the tokens that become bytes.

Comments out, blank lines out, whitespace normalised. That is what lets
`make verify-org` prove the second half of its claim: rom/dragster.asm is what
tools/disasm.py generated, annotated with comments and NOTHING else. Run both
through this and they must be identical.

Combat did not need this, because its source of record was a disassembly
somebody else had already written and it was never regenerated. Here the
generator is the authority, so "the annotations are inert" has to be a checked
claim rather than a promise -- an annotation that accidentally swallows an
instruction is then a build failure instead of a bug found weeks later.
"""
import sys


def strip_line(line):
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            out.append(ch)
            continue
        if ch == ";":
            break
        out.append(ch)
    text = "".join(out)
    if not text.strip():
        return None
    indented = text[:1].isspace()
    parts = text.split()
    return ("\t" if indented else "") + "\t".join(parts)


def main(argv):
    src = open(argv[1]) if len(argv) > 1 else sys.stdin
    for line in src:
        s = strip_line(line)
        if s is not None:
            print(s)


if __name__ == "__main__":
    main(sys.argv)
