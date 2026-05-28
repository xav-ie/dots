// Favicon glyph catalog for firefox.cfg.
//
// Loaded via Services.scriptloader.loadSubScript into a scope object, so the
// top-level `var pickFaviconIcon` below becomes a property of that object.
// Exposes pickFaviconIcon(browser) -> a data: URI string, or null to leave the
// tab's favicon untouched.
//
// All glyphs are inline SVG (URL-encoded at runtime) so they're self-contained,
// and light/monochrome so they read on a dark theme and don't trip the
// dark-favicon inverter in firefox.cfg. Tuned for the enlarged favicon size set
// in userChrome.css.

var pickFaviconIcon = (function () {
  const svgIcon = (inner) =>
    "data:image/svg+xml," +
    encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">' +
        inner +
        "</svg>",
    );

  // Shared document silhouette (page with a folded corner).
  const DOC_BODY =
    '<path d="M3.5 1h6l3 3v10.5a.5.5 0 0 1-.5.5H3.5a.5.5 0 0 1-.5-.5v-13a.5.5 0 0 1 .5-.5z" fill="#eceff4" stroke="#aab1bd" stroke-width=".6"/>' +
    '<path d="M9.5 1l3 3h-2.6a.4.4 0 0 1-.4-.4z" fill="#aab1bd"/>';

  const ICON_PDF = svgIcon(
    '<path d="M3.5 1h6l3 3v10.5a.5.5 0 0 1-.5.5H3.5a.5.5 0 0 1-.5-.5v-13a.5.5 0 0 1 .5-.5z" fill="#ffffff" stroke="#aab1bd" stroke-width=".6"/>' +
      '<path d="M9.5 1l3 3h-2.6a.4.4 0 0 1-.4-.4z" fill="#aab1bd"/>' +
      '<rect x="2.2" y="8.6" width="11.6" height="5" rx=".8" fill="#e8443b"/>' +
      '<text x="8" y="12.65" font-family="Helvetica,Arial,sans-serif" font-size="4.1" font-weight="700" fill="#ffffff" text-anchor="middle">PDF</text>',
  );

  const ICON_PAGE = svgIcon(DOC_BODY);

  const ICON_TEXT = svgIcon(
    DOC_BODY +
      '<g stroke="#8b93a1" stroke-width=".8" stroke-linecap="round">' +
      '<path d="M5 7h6"/><path d="M5 9.2h6"/><path d="M5 11.4h4"/>' +
      "</g>",
  );

  const ICON_FOLDER = svgIcon(
    '<path d="M2 4.5a1 1 0 0 1 1-1h3.2l1.3 1.5H13a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1z" fill="#cdd5e3"/>',
  );

  const ICON_CODE = svgIcon(
    '<g fill="none" stroke="#cdd5e3" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M5.5 4.5 2.5 8l3 3.5"/><path d="M10.5 4.5 13.5 8l-3 3.5"/><path d="M9 3.6 7 12.4"/>' +
      "</g>",
  );

  const ICON_JSON = svgIcon(
    '<g fill="none" stroke="#cdd5e3" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M6.6 2.8c-1.6 0-1.2 2-1.2 3.2 0 1-.6 1.8-1.6 1.8 1 0 1.6.8 1.6 1.8 0 1.2-.4 3.2 1.2 3.2"/>' +
      '<path d="M9.4 2.8c1.6 0 1.2 2 1.2 3.2 0 1 .6 1.8 1.6 1.8-1 0-1.6.8-1.6 1.8 0 1.2.4 3.2-1.2 3.2"/>' +
      "</g>",
  );

  // First match wins. Returns an icon for tabs Firefox would otherwise leave
  // with the generic globe, or null to leave the favicon untouched.
  return function pickFaviconIcon(browser) {
    let ct = "";
    let spec = "";
    let scheme = "";
    try {
      ct = browser.documentContentType || "";
    } catch (e) {}
    try {
      spec = browser.currentURI.spec || "";
      scheme = browser.currentURI.scheme || "";
    } catch (e) {}

    if (ct === "application/pdf" || /\.pdf(?:[?#]|$)/i.test(spec))
      return ICON_PDF;
    if (scheme === "view-source") return ICON_CODE;
    if (ct === "application/json" || /\.json(?:[?#]|$)/i.test(spec))
      return ICON_JSON;
    if (ct === "text/plain" || /\.(?:txt|log|csv)(?:[?#]|$)/i.test(spec))
      return ICON_TEXT;
    if (scheme === "file") return spec.endsWith("/") ? ICON_FOLDER : ICON_PAGE;
    return null;
  };
})();
