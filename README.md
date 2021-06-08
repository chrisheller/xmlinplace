# Overview

XML in-place updates

This grew out of a need for wanting to make some updates to .XML
files without making any extraneous changes that would show up when looking at diffs.

Nim's XML modules perform some normalization when processing XML, so this module uses knowledge of the parser location in the XML stream to be able to detect these corrections being applied and will undo them.

An example is that Nim's [parsexml module](https://nim-lang.org/docs/parsexml.html) will strip out leading and trailing whitespace in attribute values, so this module detects that and re-inserts the whitespace into the output.

TODO : list out the exact updates, and for each one, whether it would make sense to try to get an update into the [parsexml module](https://nim-lang.org/docs/parsexml.html).

## Usage

See the test code for sample usage.

## Tests

Identity testing. Processes all .XML files in examples/ directory
by default, but can be overridden on command line. Makes no changes
to any of the processed XML.
```
nim c -r tests/test_identity.nim
```

Change attributes / comments. Processes examples/example3.xml and
updates any attribute values that are integers by multiplying them by 25.
Also updates comment text. Output is compared to examples/example3_changed_attributes.xml.
```
nim c -r tests/test_change_attrs.nim
```

Suppress elements. Processes examples/example4.xml and removes any
elements named `child2`, including nested content. Output is compared to
examples/example4_without_child2.xml
```
nim c -r tests/test_suppress_element.nim
```
