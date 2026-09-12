// A grid, as a page.
package ui

import cortado.widgets
import std.fmt
import {Grid} from cask.engine

/// Turns a result set into an HTML page for the web view to show.
///
/// This is the one part of the browser that is not a native control, and it
/// is here because it is the thing a native table is bad at: a printable,
/// shareable, styled view of the same rows. It is also the honest test of the
/// web view — the page is built from real data, coloured by a real colour the
/// person picked, and handed to the engine as markup with no server anywhere.
///
/// It builds through a `StringBuilder` rather than by joining strings,
/// because Beans has no `+` for strings and a page of a few hundred rows is
/// exactly the case that rule exists for: every join would copy everything
/// written so far.
pub class Report {
    pub fn init() {}

    /// The page. `accent` is whatever the colour well is showing, which is
    /// how a value picked in a native control ends up as a CSS colour.
    pub fn page(title: string, grid: Grid, accent: widgets.Rgba) -> string {
        var out: fmt.StringBuilder = new fmt.StringBuilder(4096)
        self.head(out, "rgb({accent.red},{accent.green},{accent.blue})")
        out.push("<h1>{escape(title)}</h1>\n")
        if grid.column_count() == 0 {
            out.push("<p class='empty'>That statement returned no columns.</p>\n")
            return out.to_string()
        }

        out.push("<table>\n<thead><tr>")
        for name: string in grid.column_titles() {
            out.push("<th>{escape(name)}</th>")
        }
        out.push("</tr></thead>\n<tbody>\n")

        var row: int = 0
        for row < grid.row_count() {
            out.push("<tr>")
            var column: int = 0
            for column < grid.column_count() {
                let text: string = grid.cell(row, column)
                if text == "NULL" {
                    out.push("<td class='null'>NULL</td>")
                } else {
                    out.push("<td>{escape(text)}</td>")
                }
                column = column + 1
            }
            out.push("</tr>\n")
            row = row + 1
        }
        out.push("</tbody>\n</table>\n")
        out.push("<p class='count'>{grid.row_count()} rows")
        if !grid.is_complete() {
            out.push(", and the reading stopped there")
        }
        out.push("</p>\n")
        return out.to_string()
    }

    /// The stylesheet, with the accent colour spliced in.
    ///
    /// Raw strings, because a raw string opens no interpolation — which is
    /// exactly what CSS needs, since every rule in it is full of the braces
    /// an ordinary Beans string would read as the start of one. A raw string
    /// ends at the first `"`, so there is no double quote anywhere inside
    /// these three, and every attribute in the markup above is single-quoted
    /// for the same reason.
    priv fn head(out: fmt.StringBuilder, ink: string) {
        out.push(r"<!doctype html>
<meta charset='utf-8'>
<style>
  body { font: 13px -apple-system, system-ui, sans-serif; margin: 1.4rem; color: #1d1d1f }
  table { border-collapse: collapse; width: 100% }
  td { padding: .3rem .6rem; border-bottom: 1px solid #e6e6e8; vertical-align: top }
  tr:nth-child(even) td { background: #fafafa }
  td.null { color: #b0b0b5; font-style: italic }
  p.count { margin-top: .9rem; color: #6e6e73 }
  p.empty { color: #6e6e73 }
  h1 { font-size: 15px; font-weight: 600; margin: 0 0 .9rem; color: ")
        out.push(ink)
        out.push(r" }
  th { text-align: left; font-weight: 600; padding: .35rem .6rem; color: #fff;
       position: sticky; top: 0; background: ")
        out.push(ink)
        out.push(r" }
</style>
")
    }
}

/// The four characters that would otherwise make a cell into markup.
///
/// A browser shows whatever is in the file it was pointed at, and a cell
/// containing `<script>` is a perfectly legal string to store in SQLite. The
/// ampersand goes first: escaping it after the others would double-escape the
/// `&` each of them just introduced.
pub fn escape(text: string) -> string {
    return text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
}
