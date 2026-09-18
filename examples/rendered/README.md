# Rendered gallery

From the Cortado directory, open the full gallery:

```sh
../../beans/build/beansc run examples/rendered/main.b -- --gallery
```

The local Skia engine must be built first. If it is missing:

```sh
python3 tools/prepare_skia.py
```

Use the navigation buttons to test controls, text editing, scrolling, tables,
custom controls, theme changes, drawing, animation, and accessibility. The
Graphics page selects a rendering backend and can return to software rendering.
The Tables page has 10,000 rows; edit a Cup cell and press Return to save it.

To save an image of every page without opening a window:

```sh
../../beans/build/beansc run examples/rendered/main.b -- --gallery-snapshot
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
