## This module is for some enhancements that should
## probably live in xmltree.nim in the standard library.
## 
## `addEscapedAttr` is in xmltree.nim already, but it is
## not publicly accessible.
## 

import strutils

const
  AttrChars* = { '&', '<', '>', '"' }
    ## All the characters that should be escaped in XML
    ## attribute values ( '&', '<', '>', '"' )

  AttrExpandSize* = 5
    ## Estimated size for escaping an attribute character.
    ## This is used to estimate how large the expanded string
    ## will be.

proc countAttrsToEscape*(s: string) : int =
  ## Assuming `s` will be used as an XML attribute value,
  ## returns the number of characters that need to be escaped
  result = s.count(AttrChars)

proc addEscapedAttr*(result: var string, s: string) =
  ## The same as `result.add(escapeAttr(s)) <#escapeAttr,string>`_, but more efficient.
  for c in items(s):
    case c
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '&': result.add("&amp;")
    of '"': result.add("&quot;")
    else: result.add(c)

proc escapeAttr*(s: string) : string =
  ## Escapes `s` for inclusion into an XML document
  ## as an XML attribute value.
  ##
  ## Escapes these characters:
  ##
  ## ------------    -------------------
  ## char            is converted to
  ## ------------    -------------------
  ##  ``<``          ``&lt;``
  ##  ``>``          ``&gt;``
  ##  ``&``          ``&amp;``
  ##  ``"``          ``&quot;``
  ## ------------    -------------------
  ##
  ## You can also use `addEscapedAttr proc <#addEscapedAttr,string,string>`_.

  let quoteCount = s.countAttrsToEscape()
  if quoteCount == 0: # nothing to escape
    return s

  result = newStringOfCap(s.len() + quoteCount * AttrExpandSize)
  result.addEscapedAttr(s)
