/**
 * CloudFront Function — request viewer event
 *
 * Rewrites directory-style paths (e.g. /about, /about/, /posts/) to
 * append /index.html so that S3 (via OAC, no website hosting) can serve
 * the correct object key.
 *
 * Examples:
 *   /about      → /about/index.html
 *   /about/     → /about/index.html
 *   /           → /index.html          (already handled by default_root_object)
 *   /posts/     → /posts/index.html
 *   /image.png  → (unchanged)
 *   /style.css  → (unchanged)
 *   /page/1/    → /page/1/index.html
 *   /page/1     → /page/1/index.html
 */
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // If the URI ends with a file extension, serve as-is.
    if (uri.match(/\.[a-zA-Z0-9]+$/)) {
        return request;
    }

    // If the URI already ends with /index.html, serve as-is.
    if (uri.endsWith('/index.html')) {
        return request;
    }

    // Append /index.html
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    } else {
        request.uri = uri + '/index.html';
    }

    return request;
}
