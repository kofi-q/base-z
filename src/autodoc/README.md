# Zig Autodocs

This is modified copy of Zig's [autodoc](https://github.com/ziglang/zig/tree/master/lib/docs) code, tweaked mostly to prioritise presenting public-facing aliases for decls when possible. Not fully ironed out and may result in some unexpected detail-hiding.

Also included:
- Styling updates
- Filtering out `std` decls in favour of linking out to the official docs instead.
- Syntax highlighting for code snippets in doc comments.
  - Identifier links in the rendered Zig code is still WIP and will not link to the appropriate page.
- Expanded doc comments on overview pages for namespaces.

## Original License

The MIT License (Expat)

Copyright (c) Zig contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
