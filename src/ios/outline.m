// No outline view here, and why.
//
// UIKit has no such control. The shape a phone uses is a UICollectionView
// with a list layout and section snapshots — a layout applied to a different
// control, with a different data source and a different lifetime — so
// ctd_widget_supports(CTD_W_OUTLINE_VIEW) answers 0 and every call below
// refuses by name rather than half-working against something else.
//
// The refusals are still written out one by one rather than behind a macro,
// because each one is the answer a caller gets and "unsupported" from a named
// function is what makes a missing control diagnosable.

#import "internal.h"

ctd_status ctd_set_outline_source(ctd_outline_fn shape, void *shape_context,
                                  ctd_outline_text_fn text, void *text_context) {
    (void)shape; (void)shape_context; (void)text; (void)text_context;
    // Registering a source is not itself a refusal: a program that registers
    // one and then finds no control can build is told by the control, which
    // is where the answer belongs. Answering an error here would make every
    // portable program handle a failure that means nothing.
    return CTD_OK;
}

ctd_status ctd_outline_columns(ctd_handle outline, int32_t count) {
    (void)count;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_column_title(ctd_handle outline, int32_t column,
                                    const char *utf8, int32_t len) {
    (void)column; (void)utf8; (void)len;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_column_width(ctd_handle outline, int32_t column,
                                    double points) {
    (void)column; (void)points;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_reload(ctd_handle outline) {
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_expand(ctd_handle outline, int64_t node, int32_t on) {
    (void)node; (void)on;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_expanded(ctd_handle outline, int64_t node, int32_t *out) {
    (void)node; (void)out;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_selected(ctd_handle outline, int64_t *out) {
    (void)out;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

ctd_status ctd_outline_select(ctd_handle outline, int64_t node) {
    (void)node;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}

int32_t ctd_outline_cell(ctd_handle outline, int64_t node, int32_t column,
                         char *out, int32_t cap) {
    (void)node; (void)column; (void)out; (void)cap;
    return ctd_resolve(outline) ? CTD_ERR_KIND : CTD_ERR_STALE;
}
