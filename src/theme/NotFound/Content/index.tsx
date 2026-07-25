import { type ReactNode } from 'react';
import Custom404 from '../../../components/Custom404';

/**
 * Custom NotFound Content Component
 * This is the proper Docusaurus way to handle ALL 404s globally,
 * including docs routes, page routes, and any other missing content.
 *
 * Deliberately passes no extra links. Every site built from this template
 * inherits this component, and only "/" is guaranteed to resolve everywhere:
 * a consumer may serve docs from the site root or disable the pages plugin,
 * in which case routes such as /docs and /demos do not exist — warning during
 * their build, and failing it outright if they set `onBrokenLinks: 'throw'`.
 * A site that does have those routes can pass them here, but must then accept
 * that it owns this override.
 *
 * `__tests__/index.test.tsx` asserts this renders exactly one link, to "/".
 */
export default function ContentWrapper(): ReactNode {
  return (
    <>
      <Custom404 />
    </>
  );
}
