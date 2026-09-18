# Rendered gallery

From the Cortado directory, open the compiled gallery:

```sh
./build/rendered --gallery
```

After source changes, rebuild it first:

```sh
BEANS_RUNTIME=../../beans/runtime/beans_rt.c \
BEANS_STDLIB=../../beans/stdlib/std \
BEANS_ENCODING=../../beans/runtime/encoding \
BEANS_NET=../../beans/runtime/net \
BEANS_LOG=../../beans/runtime/log \
../../beans/build/beansc build examples/rendered/main.b -o build/rendered
```

Use the compiled binary for performance testing. `beansc run` uses the interpreter.

The local Skia engine must be built first. If it is missing:

```sh
python3 tools/prepare_skia.py
```

Use the navigation buttons to test controls, text editing, scrolling, tables,
custom controls, theme changes, drawing, animation, and accessibility. The
Graphics page selects a rendering backend and can return to software rendering.
The Tables page has 10,000 rows. Double-click a Cup cell to edit it. Return saves;
Escape cancels. Use Up/Down to select a row and Left/Right to select a column,
then Return to edit. Scrolling an editor fully out of view cancels its draft.

To save an image of every page without opening a window:

```sh
./build/rendered --gallery-snapshot
```

Images are written to `build/rendered-gallery-*.png`.

Markup lives in `site/`, with snake_case filenames and PascalCase class names.
Generated Beans mirrors those files in `generated/site/`, the
`rendered_demo.generated.site` package. After editing markup, regenerate it:

```sh
../../beans/build/beansc build examples/cortado_bx.b -o build/cortado-bx
build/cortado-bx build templates
build/cortado-bx build examples/rendered/site
```

Framework templates live in `templates/*.bx`; generated classes belong to
`cortado.generated.templates`. `cortado.templates.DefaultTemplates` selects them.
Do not edit the generated files directly.

Run `python3 tools/test_rendered.py --sanitize` for the shared test suite.
See [RENDERING.md](../../RENDERING.md) for platform support and work still needed.

For a repeatable table timing run, see [the table benchmark](benchmarks/table/README.md).
