## This module exists to workaround a couple of places where
## ``parsexml.nim`` does not provide exactly the functionality
## that we need. This entire module could potentially be removed
## with better access in parsexml.nim to whitespace handling, etc.
## (no attempt has been made yet to upstream any of this stuff
##  yet though)
## 
## One example is that when parsexml processes XML attributes,
## it will remove embedded CR/LF, and it drops trailing whitespace
## For most XML, that is not an issue, but our goal is to be able
## modify XML files/streams without making extraneous updates to
## the output. Instead, this module provides a ``parseAttrValue``
## proc that will preserve that whitespace. A cloned version of
## ``parseEntity`` and ``parseName`` from parsexml are used here
## that allow preserving the whitespace. The cloned versions do not
## modify the internal parser state like the originals do (since we
## are essentially re-processing the attribute). We also leave out
## the error handling in the clones since any errors would have been
## hit by the original procs during the initial parsing. 
##

import strutils, unicode
from parsexml import XmlParser

const
  NameStartChar = {'A'..'Z', 'a'..'z', '_', ':', '\128'..'\255'}
  NameChar = {'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', ':', '\128'..'\255'}

proc parseName(s: string, start: Natural = 0, dest: var string) : Natural =
  # Returns the size of the name that was parsed
  var pos = start
  if s[pos] in NameStartChar:
    while true:
      add(dest, s[pos])
      inc(pos)
      if s[pos] notin NameChar: break
    result = pos - start

proc parseEntity*(s: string, start: Natural = 0, dest: var string) : Natural =
  assert(s[start] == '&')
  var pos = start + 1
  if s[pos] == '#':
    var r: int
    inc(pos)
    if s[pos] == 'x':
      inc(pos)
      while true:
        case s[pos]
        of '0'..'9': r = (r shl 4) or (ord(s[pos]) - ord('0'))
        of 'a'..'f': r = (r shl 4) or (ord(s[pos]) - ord('a') + 10)
        of 'A'..'F': r = (r shl 4) or (ord(s[pos]) - ord('A') + 10)
        else: break
        inc(pos)
    else:
      while s[pos] in {'0'..'9'}:
        r = r * 10 + (ord(s[pos]) - ord('0'))
        inc(pos)
    add(dest, toUTF8(Rune(r)))
  elif s[pos] == 'l' and s[pos+1] == 't' and s[pos+2] == ';':
    add(dest, '<')
    inc(pos, 2)
  elif s[pos] == 'g' and s[pos+1] == 't' and s[pos+2] == ';':
    add(dest, '>')
    inc(pos, 2)
  elif s[pos] == 'a' and s[pos+1] == 'm' and s[pos+2] == 'p' and
      s[pos+3] == ';':
    add(dest, '&')
    inc(pos, 3)
  elif s[pos] == 'a' and s[pos+1] == 'p' and s[pos+2] == 'o' and
      s[pos+3] == 's' and s[pos+4] == ';':
    add(dest, '\'')
    inc(pos, 4)
  elif s[pos] == 'q' and s[pos+1] == 'u' and s[pos+2] == 'o' and
      s[pos+3] == 't' and s[pos+4] == ';':
    add(dest, '"')
    inc(pos, 4)
  else:
    var name = ""
    pos += parseName(s, pos, name)
    add(dest, '&')
    add(dest, name)
  if s[pos] == ';':
    inc(pos)
  result = pos - start

proc parseAttrValue*(s: string) : string =
  if not s.contains('&'):
    return s

  result = newStringOfCap(s.len())
  var i = s.low
  while i <= s.high:
    if s[i] ==  '&':
      let count = parseEntity(s, i, result)
      inc(i, count)
    else:
      result.add(s[i])
      inc(i)

proc isEmptyElementTag*(x: XmlParser) : bool =
  ## This determines if a start tag is actually an empty element tag
  ## or not. This intentionally does not advance the parser to "swallow"
  ## the xmlElementEnd event that will occur next if we are on
  ## an empty element tag, so calling code needs to be aware of this.

  var pos = x.bufpos
  assert(x.buf[pos-1] == '>')
  pos -= 2
  result = x.buf[pos] == '/'

proc getWhitespace*(x: XmlParser, fromPos : Natural) : string =
  ## Helper proc for extracting whatever whitespace the parser
  ## just read. ``fromPos`` is the position in the parser buffer
  ## where the *end* of the whitespace is.
  ## 
  var
    wsPos = fromPos
    wsCount = 0
  while x.buf[wsPos] in Whitespace:
    dec(wsPos)
    inc(wsCount)

  if wsCount == 0:
    return ""

  let
    start = fromPos - wsCount + 1
    finish = start + wsCount - 1
  result = x.buf.substr(start, finish)
