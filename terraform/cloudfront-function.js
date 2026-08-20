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

    // If the URI ends with a known static-asset extension, serve as-is.
    // A generic "ends with .anything" check would misfire on directory-style
    // slugs that happen to contain a dot (e.g. /posts/aws-v1.2), treating
    // them as files and skipping the /index.html rewrite below.
    if (uri.match(/\.(html|xml|css|js|mjs|json|txt|ico|png|jpg|jpeg|gif|svg|webp|webmanifest|woff2?|ttf|eot|pdf|map)$/i)) {
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
